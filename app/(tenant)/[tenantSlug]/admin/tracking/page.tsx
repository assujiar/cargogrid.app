import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantTrackingPackage, resolveTenantTrackingSourcePolicy, TrackingSourcePolicyQueryError } from "../../../../../server/queries/tracking-source-policy.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { TrackingSourcePolicyPanel } from "./tracking-panel.tsx";
import { upsertTrackingSourcePolicyAction } from "./actions.ts";
import type { TrackingPackageResolution, ResolvedTenantTrackingSourcePolicy } from "../../../../../server/contracts/tracking-source-policy/tracking-source-policy.ts";

/**
 * Tenant tracking package and source policy admin screen (ATW-226H, closing the gap
 * ATW-226A's own build log explicitly named: "No UI exists yet for assigning a
 * tracking package or editing the tenant-level source policy -- deferred to
 * ATW-226H"). Package/entitlement *assignment* remains read-only here -- it is a
 * generic Configuration Engine draft/publish workflow (PLT-121), the same "reuse the
 * generic engine, do not fork it" decision ATW-226A's own migration header already
 * made, and no generic config-draft/publish UI exists anywhere in this repository yet
 * to build a bounded editor on top of; the *source policy* (priority/freshness/
 * accuracy/hysteresis) has its own dedicated, simple upsert RPC and is fully editable
 * below.
 */
export default async function TenantAdminTrackingPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const tenantId = access.tenant.id;

  let loadFailed = false;
  let trackingPackage: TrackingPackageResolution | null = null;
  let sourcePolicy: ResolvedTenantTrackingSourcePolicy | null = null;
  try {
    const [pkg, policy] = await Promise.all([resolveTenantTrackingPackage(supabase, tenantId), resolveTenantTrackingSourcePolicy(supabase, tenantId)]);
    trackingPackage = pkg;
    sourcePolicy = policy;
  } catch (error) {
    if (!(error instanceof TrackingSourcePolicyQueryError)) {
      throw error;
    }
    loadFailed = true;
  }

  if (loadFailed || !trackingPackage || !sourcePolicy) {
    return (
      <div className="flex flex-col gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">Tracking</h1>
        <ErrorState description="Something went wrong loading the tracking package and source policy. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Tracking</h1>
        <p className="text-xs text-neutral-500">Tracking package entitlement (read-only) and the tenant-default source arbitration policy.</p>
      </div>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Package entitlement</h2>
        {trackingPackage.enabled ? (
          <dl className="grid grid-cols-2 gap-2 text-sm sm:grid-cols-4">
            <div>
              <dt className="text-xs text-neutral-500">Package</dt>
              <dd className="text-neutral-900">{trackingPackage.packageCode ?? "—"}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Max tracked vehicles</dt>
              <dd className="text-neutral-900">{trackingPackage.maxTrackedVehicles ?? "unlimited"}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">Max mobile sessions</dt>
              <dd className="text-neutral-900">{trackingPackage.maxMobileSessions ?? "unlimited"}</dd>
            </div>
            <div>
              <dt className="text-xs text-neutral-500">History retention</dt>
              <dd className="text-neutral-900">{trackingPackage.historyRetentionDays ? `${trackingPackage.historyRetentionDays} days` : "unlimited"}</dd>
            </div>
          </dl>
        ) : (
          <p className="text-sm text-neutral-500">
            No tracking package is assigned to this organization yet. GPS/telematics ingestion is not entitled until Supreme Admin assigns one.
          </p>
        )}
      </section>

      <TrackingSourcePolicyPanel sourcePolicy={sourcePolicy} action={upsertTrackingSourcePolicyAction.bind(null, tenantSlug)} />
    </div>
  );
}
