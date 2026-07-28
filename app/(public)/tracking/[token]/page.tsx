import { createHash } from "node:crypto";
import { headers } from "next/headers";
import { createSupabaseServiceRoleClient } from "../../../../lib/supabase/service-role.ts";
import { lookupPublicShipmentTracking } from "../../../../server/queries/public-tracking.ts";

const STATUS_MESSAGE: Record<string, string> = {
  not_found: "This tracking link doesn't match any shipment. Please check the link or contact your logistics provider.",
  invalid: "This tracking link doesn't match any shipment. Please check the link or contact your logistics provider.",
  rate_limited: "Too many lookups from this connection. Please try again in a few minutes.",
};

/**
 * Public shipment tracking page (OPS-180, CG-S8-OPS-014). Deliberately outside every
 * tenant-authenticated portal guard (`app/(public)/`, the same route group
 * `app/(public)/login/` and `app/(public)/quote-decision/[token]/` already
 * established) -- the party holding this link has no CargoGrid account. Reads via a
 * service-role client (no `auth.uid()` session exists here) and the one
 * `app.lookup_public_shipment_tracking` RPC, which always resolves to a row (never
 * throws) -- every outcome, including a bad/expired/revoked token or a rate-limited
 * caller, is rendered here rather than a crash.
 *
 * client_key is a sha256 hash of the caller's own best-effort IP address
 * (`x-forwarded-for`, the same disclosed "no verified identity" limitation
 * `app/(public)/quote-decision/[token]/actions.ts` already recorded) -- never the raw
 * IP itself, since app.tracking_lookup_attempts is retained as rate-limit evidence.
 */
export default async function PublicTrackingPage({ params }: { params: Promise<{ token: string }> }) {
  const { token } = await params;
  const requestHeaders = await headers();
  const ipAddress = requestHeaders.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  const clientKey = createHash("sha256").update(ipAddress).digest("hex");

  const client = createSupabaseServiceRoleClient();
  const result = await lookupPublicShipmentTracking(client, { rawToken: token, clientKey });

  if (result.lookupStatus !== "ok") {
    return (
      <main className="mx-auto flex min-h-screen max-w-md flex-col items-center justify-center gap-3 px-4 text-center">
        <h1 className="text-xl font-semibold text-neutral-900">Tracking unavailable</h1>
        <p className="text-sm text-neutral-600">{STATUS_MESSAGE[result.lookupStatus] ?? "This tracking link is no longer valid."}</p>
      </main>
    );
  }

  return (
    <main className="mx-auto flex min-h-screen max-w-2xl flex-col gap-6 px-4 py-10">
      <h1 className="text-xl font-semibold text-neutral-900">Shipment {result.shipmentNumber}</h1>

      <dl className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
        <dt className="font-medium text-neutral-600">Status</dt>
        <dd className="text-neutral-900">{result.status}</dd>
        <dt className="font-medium text-neutral-600">Mode</dt>
        <dd className="text-neutral-900">{result.mode}</dd>
        <dt className="font-medium text-neutral-600">Origin</dt>
        <dd className="text-neutral-900">{result.origin}</dd>
        <dt className="font-medium text-neutral-600">Destination</dt>
        <dd className="text-neutral-900">{result.destination}</dd>
        <dt className="font-medium text-neutral-600">Planned delivery</dt>
        <dd className="text-neutral-900">{result.plannedDeliveryAt ? new Date(result.plannedDeliveryAt).toLocaleDateString() : "—"}</dd>
        {result.currentEta ? (
          <>
            <dt className="font-medium text-neutral-600">Current ETA</dt>
            <dd className="text-neutral-900">
              {new Date(result.currentEta).toLocaleDateString()}
              {result.isDelayed ? " (delayed)" : ""}
            </dd>
          </>
        ) : null}
      </dl>

      {result.epodAvailable ? (
        <p role="status" className="rounded-md border border-neutral-200 p-3 text-sm text-neutral-900">
          Proof of delivery is available for this shipment. Please contact your logistics provider for a copy.
        </p>
      ) : null}

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Milestones</h2>
        {result.milestones.length === 0 ? (
          <p className="text-sm text-neutral-500">No milestones recorded yet.</p>
        ) : (
          <ul className="flex flex-col gap-2">
            {result.milestones.map((milestone, index) => (
              <li key={`${milestone.code}-${index}`} className="flex items-center gap-3 rounded-md border border-neutral-200 p-3 text-sm">
                <span className="font-medium text-neutral-900">{milestone.code.replace(/_/g, " ")}</span>
                <span className="text-neutral-600">{new Date(milestone.eventTime).toLocaleString()}</span>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}
