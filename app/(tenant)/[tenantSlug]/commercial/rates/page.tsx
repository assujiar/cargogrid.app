import { notFound } from "next/navigation";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listActiveVendorRates, listPendingRateVersions, RateQueryError } from "../../../../../server/queries/rate.ts";
import type { RateVersion } from "../../../../../server/contracts/rate/rate.ts";
import { DataTable, type DataTableColumn } from "../../../../../components/tables/data-table.tsx";
import { createRateVersionAction } from "./actions.ts";
import { CreateRateVersionForm } from "./create-rate-form.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";

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

  const pendingColumns: readonly DataTableColumn<RateVersion>[] = [
    {
      key: "vendor",
      header: "Vendor",
      render: (rate) => (
        <a href={`/${tenantSlug}/commercial/rates/${rate.rateVersionId}`} className="font-medium text-primary underline">
          {rate.vendorName}
        </a>
      ),
    },
    { key: "lane", header: "Lane", render: (rate) => `${rate.originLane} → ${rate.destinationLane}` },
    { key: "service", header: "Service", render: (rate) => `${rate.serviceType}${rate.mode ? ` (${rate.mode})` : ""}` },
  ];

  const activeColumns: readonly DataTableColumn<RateVersion>[] = [
    ...pendingColumns,
    { key: "cost", header: "Cost", render: (rate) => (rate.costMasked ? "Restricted" : `${rate.baseAmount} ${rate.currency ?? ""}`) },
  ];

  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Vendor rates</h1>

      {loadFailed ? (
        <ErrorState description="Something went wrong loading vendor rates. Please try again." />
      ) : (
        <>
          {pendingRates.length > 0 ? (
            <div className="rounded-md border border-neutral-200 p-4">
              <h2 className="text-sm font-semibold text-neutral-900">Pending approval</h2>
              <div className="mt-2">
                <DataTable
                  caption="Pending vendor rates"
                  columns={pendingColumns}
                  rows={pendingRates}
                  rowKey={(rate) => rate.rateVersionId}
                  emptyMessage="No pending rate versions."
                />
              </div>
            </div>
          ) : null}

          <div className="rounded-md border border-neutral-200 p-4">
            <h2 className="text-sm font-semibold text-neutral-900">Active rates</h2>
            <div className="mt-2">
              <DataTable
                caption="Active vendor rates"
                columns={activeColumns}
                rows={activeRates}
                rowKey={(rate) => rate.rateVersionId}
                emptyMessage="No approved, currently-effective rates yet. Create one below."
              />
            </div>
          </div>
        </>
      )}

      <CreateRateVersionForm action={boundCreateAction} />
    </div>
  );
}
