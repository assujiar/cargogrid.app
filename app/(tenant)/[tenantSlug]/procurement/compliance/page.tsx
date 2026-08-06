import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listTenantVendorComplianceMatrix, VendorComplianceQueryError } from "../../../../../server/queries/vendor-compliance.ts";
import type { VendorComplianceStatusValue } from "../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ComplianceMatrixPanel } from "./compliance-matrix-panel.tsx";
import { recalculateTenantVendorComplianceStatusAction } from "./actions.ts";

/**
 * Vendor compliance matrix (PRC-253, CG-S11-PRC-004) -- a vendor x requirement grid,
 * server-filtered and cursor-paginated (Sec.15/17). The SAME table also serves as the
 * expiry/reminders queue: pass `?status=expiring_soon`, `?status=expired`, or
 * `?hold=1` to narrow it to exactly the rows staff need to act on -- a disclosed
 * simplification (one flexible table, several presets) rather than a second,
 * structurally-identical route.
 */
export default async function VendorCompliancePage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string }>;
  searchParams: Promise<{ status?: string; hold?: string; after?: string }>;
}) {
  const { tenantSlug } = await params;
  const { status, hold, after } = await searchParams;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as VendorComplianceStatusValue) : null) ?? null;
  const holdOnly = hold === "1";

  let loadFailed = false;
  let rows: Awaited<ReturnType<typeof listTenantVendorComplianceMatrix>> = [];
  try {
    rows = await listTenantVendorComplianceMatrix(supabase, access.tenant.id, access.authUserId, { statusFilter, holdOnly, limit: 100, afterId: after ?? null });
  } catch (error) {
    if (!(error instanceof VendorComplianceQueryError) && !(error instanceof Error)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the compliance matrix. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Vendor compliance</h1>
          <p className="text-xs text-neutral-500">Requirement coverage, expiry and eligibility holds across every vendor. Filter to expiring/expired for the reminders queue, or to holds only.</p>
        </div>
        <a href={`/${tenantSlug}/procurement/compliance/requirements`} className="text-sm text-primary underline">
          Manage requirements
        </a>
      </div>

      <ComplianceMatrixPanel
        tenantSlug={tenantSlug}
        rows={rows}
        statusFilter={statusFilter}
        holdOnly={holdOnly}
        recalculateTenantAction={recalculateTenantVendorComplianceStatusAction.bind(null, tenantSlug)}
      />
    </div>
  );
}
