import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listActiveVendorRates, listPendingRateVersions, RateQueryError } from "../../../../../server/queries/rate.ts";
import type { RateVersion } from "../../../../../server/contracts/rate/rate.ts";
import { createRateVersionAction } from "./actions.ts";
import { CreateRateVersionForm } from "./create-rate-form.tsx";

/**
 * Vendor Rate list (COM-149, CG-S7-COM-008). Two tables reading through the field-masked
 * app.v_active_vendor_rates / app.vendor_rate_versions_directory views (cost columns
 * withheld without COM:View cost), plus a create form -- app.create_rate_version is
 * gated by app.is_support_grant_authority (tenant_admin/Supreme Admin), not ordinary
 * COM:Create, so this form renders for every Commercial portal user; an actor lacking
 * that authority sees the real server-side denial, the same "don't hide buttons based on
 * client-side authority-guessing" posture every prior Commercial page already uses.
 * Disclosed UI scope boundary: no lane/service filter or comparison sort here -- the
 * fully tested app.search_vendor_rates RPC is ready for a richer lookup UI, but this
 * bounded slice ships the two tables (active, pending) plus create/review-by-detail-page,
 * matching every other Commercial list page's own bounded-first-iteration convention.
 */
export default async function CommercialRatesPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let activeRates: RateVersion[];
  let pendingRates: RateVersion[];
  let loadFailed = false;
  try {
    [activeRates, pendingRates] = await Promise.all([
      listActiveVendorRates(supabase, access.tenant.id),
      listPendingRateVersions(supabase, access.tenant.id),
    ]);
  } catch (error) {
    if (!(error instanceof RateQueryError)) {
      throw error;
    }
    loadFailed = true;
    activeRates = [];
    pendingRates = [];
  }

  const boundCreateAction = createRateVersionAction.bind(null, tenantSlug);

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Vendor rates</h1>

      {loadFailed ? (
        <div role="alert" className="flex flex-col gap-2">
          <p className="text-sm text-danger">Something went wrong loading vendor rates. Please try again.</p>
        </div>
      ) : (
        <>
          {pendingRates.length > 0 ? (
            <div className="rounded-md border border-neutral-200 p-4">
              <h2 className="text-sm font-semibold text-neutral-900">Pending approval</h2>
              <table className="mt-2 w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-neutral-600">
                    <th scope="col" className="py-2 pr-4 font-medium">Vendor</th>
                    <th scope="col" className="py-2 pr-4 font-medium">Lane</th>
                    <th scope="col" className="py-2 font-medium">Service</th>
                  </tr>
                </thead>
                <tbody>
                  {pendingRates.map((rate) => (
                    <tr key={rate.rateVersionId} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">
                        <a href={`/${tenantSlug}/commercial/rates/${rate.rateVersionId}`} className="font-medium text-primary underline">
                          {rate.vendorName}
                        </a>
                      </td>
                      <td className="py-2 pr-4 text-neutral-600">{rate.originLane} → {rate.destinationLane}</td>
                      <td className="py-2 text-neutral-600">{rate.serviceType}{rate.mode ? ` (${rate.mode})` : ""}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          ) : null}

          <div className="rounded-md border border-neutral-200 p-4">
            <h2 className="text-sm font-semibold text-neutral-900">Active rates</h2>
            {activeRates.length === 0 ? (
              <p className="mt-2 text-sm text-neutral-600">No approved, currently-effective rates yet. Create one below.</p>
            ) : (
              <table className="mt-2 w-full border-collapse text-sm">
                <thead>
                  <tr className="border-b border-neutral-200 text-left text-neutral-600">
                    <th scope="col" className="py-2 pr-4 font-medium">Vendor</th>
                    <th scope="col" className="py-2 pr-4 font-medium">Lane</th>
                    <th scope="col" className="py-2 pr-4 font-medium">Service</th>
                    <th scope="col" className="py-2 font-medium">Cost</th>
                  </tr>
                </thead>
                <tbody>
                  {activeRates.map((rate) => (
                    <tr key={rate.rateVersionId} className="border-b border-neutral-100">
                      <td className="py-2 pr-4 text-neutral-900">
                        <a href={`/${tenantSlug}/commercial/rates/${rate.rateVersionId}`} className="font-medium text-primary underline">
                          {rate.vendorName}
                        </a>
                      </td>
                      <td className="py-2 pr-4 text-neutral-600">{rate.originLane} → {rate.destinationLane}</td>
                      <td className="py-2 pr-4 text-neutral-600">{rate.serviceType}{rate.mode ? ` (${rate.mode})` : ""}</td>
                      <td className="py-2 text-neutral-600">{rate.costMasked ? "Restricted" : `${rate.baseAmount} ${rate.currency ?? ""}`}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </>
      )}

      <CreateRateVersionForm action={boundCreateAction} />
    </div>
  );
}
