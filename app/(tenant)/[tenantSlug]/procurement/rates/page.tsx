import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listProcurementLinkedVendorRateVersions, ProcurementRateQueryError } from "../../../../../server/queries/procurement-rate.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { RateDirectoryPanel, type ProcurementRateRow } from "./rate-directory-panel.tsx";
import { createProcurementRateVersionAction } from "./actions.ts";

/**
 * Vendor Rate and Pricelist directory (PRC-255, CG-S11-PRC-006) -- extends
 * app/(tenant)/[tenantSlug]/commercial/rates/page.tsx's own shape into the
 * Procurement workspace, scoped to rates linked to a real registered vendor
 * (ADR-0020). Tiers, calculation preview, and approval live on each rate's own
 * detail page (Prompt 255 §15: "structured editor/tier grid... calculation
 * preview... approval/version timeline").
 */
export default async function ProcurementRateDirectoryPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let rows: Record<string, unknown>[] = [];
  try {
    rows = await listProcurementLinkedVendorRateVersions(supabase, access.tenant.id);
  } catch (error) {
    if (!(error instanceof ProcurementRateQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor rate directory. Please try again." />;
  }

  const rates: ProcurementRateRow[] = rows.map((row) => ({
    rateVersionId: String(row.rate_version_id),
    vendorCode: String(row.vendor_code),
    vendorName: String(row.vendor_name),
    serviceType: String(row.service_type),
    originLane: String(row.origin_lane),
    destinationLane: String(row.destination_lane),
    approvalStatus: row.approval_status as ProcurementRateRow["approvalStatus"],
    currency: (row.currency as string | null) ?? null,
    baseAmount: (row.base_amount as number | null) ?? null,
    costMasked: Boolean(row.cost_masked),
    vendorMasterId: (row.vendor_master_id as string | null) ?? null,
  }));

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor rates and pricelists</h1>
        <p className="text-xs text-neutral-500">
          The canonical vendor-rate engine (Phase 2, ADR-0015), extended with vendor identity linkage, weight/volume tiers, and lead-time/capacity terms (Phase 6, ADR-0020).
          Vendor cost figures are masked here without PRC:View cost.
        </p>
      </div>

      <RateDirectoryPanel tenantSlug={tenantSlug} rates={rates} createAction={createProcurementRateVersionAction.bind(null, tenantSlug)} />
    </div>
  );
}
