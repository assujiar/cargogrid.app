import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listVendorComparisons, VendorComparisonQueryError } from "../../../../../server/queries/vendor-comparison.ts";
import { VENDOR_COMPARISON_STATUSES, type VendorComparisonStatus } from "../../../../../server/contracts/vendor-comparison/vendor-comparison.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { VendorComparisonQueuePanel } from "./vendor-comparison-queue-panel.tsx";
import { createVendorComparisonAction } from "./actions.ts";

/**
 * Vendor Comparison queue (PRC-258, CG-S11-PRC-009) -- comparisons built from
 * a closed app.rfqs (PRC-257), filterable by status. With no status filter,
 * superseded (historical, non-current) versions are excluded by default.
 * Mirrors app/(tenant)/[tenantSlug]/procurement/rfq/page.tsx's own exact
 * shape.
 */
export default async function VendorComparisonQueuePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status } = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const statusFilter: VendorComparisonStatus | null =
    status && (VENDOR_COMPARISON_STATUSES as readonly string[]).includes(status) ? (status as VendorComparisonStatus) : null;

  const supabase = await createSupabaseServerClient();

  let loadFailed = false;
  let deniedForCost = false;
  let comparisons: Awaited<ReturnType<typeof listVendorComparisons>> = [];
  try {
    comparisons = await listVendorComparisons(supabase, access.tenant.id, access.authUserId, null, statusFilter, 100);
  } catch (error) {
    if (!(error instanceof VendorComparisonQueryError)) throw error;
    if (error.message.includes("insufficient_authority")) {
      deniedForCost = true;
    } else {
      loadFailed = true;
    }
  }

  if (deniedForCost) {
    return (
      <ErrorState
        title="Cost data access required"
        description="Viewing vendor comparisons requires the Procurement: View cost permission -- comparisons expose normalized vendor pricing by design (ADR-0020)."
      />
    );
  }
  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the vendor comparison queue. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Vendor Comparison</h1>
        <p className="text-xs text-neutral-500">
          Compare eligible, comparison-ready RFQ responses on an exact common basis -- normalized currency and, where an approved vendor rate is linked, the exact rate-engine amount.
          Lowest price is never automatic selection; every recommendation and human override is auditable.
        </p>
      </div>

      <VendorComparisonQueuePanel tenantSlug={tenantSlug} comparisons={comparisons} statusFilter={statusFilter} createAction={createVendorComparisonAction.bind(null, tenantSlug)} />
    </div>
  );
}
