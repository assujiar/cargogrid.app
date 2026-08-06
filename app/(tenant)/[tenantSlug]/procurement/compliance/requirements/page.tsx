import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listVendorComplianceRequirements, VendorComplianceQueryError } from "../../../../../../server/queries/vendor-compliance.ts";
import type { VendorComplianceRequirementStatus } from "../../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { RequirementManagementPanel } from "./requirement-management-panel.tsx";
import { createVendorComplianceRequirementDraftAction } from "../actions.ts";

/**
 * Vendor compliance requirement management (PRC-253, CG-S11-PRC-004) --
 * draft/publish/archive requirements scoped by vendor category/service, mirroring
 * app/(tenant)/[tenantSlug]/procurement/assessments/templates/page.tsx's own shape.
 * Procurement/compliance admin only in practice: the create/publish/archive RPCs
 * themselves gate on PRC:Create/Edit/Approve, so any PRC:View holder can view this
 * screen but every mutating control will surface insufficient_authority if attempted
 * (server-enforced, not merely hidden).
 */
export default async function VendorComplianceRequirementsPage({
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

  const supabase = await createSupabaseServerClient();
  const statusFilter = (status && status.length > 0 ? (status as VendorComplianceRequirementStatus) : null) ?? null;

  let loadFailed = false;
  let requirements: Awaited<ReturnType<typeof listVendorComplianceRequirements>> = [];
  try {
    requirements = await listVendorComplianceRequirements(supabase, access.tenant.id, access.authUserId, { statusFilter, limit: 100 });
  } catch (error) {
    if (!(error instanceof VendorComplianceQueryError) && !(error instanceof Error)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading compliance requirements. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Compliance requirements</h1>
        <p className="text-xs text-neutral-500">Versioned draft → published → archived requirements, scoped by vendor category and service. A published requirement&rsquo;s document type, expiry expectation, and reminder schedule are snapshotted onto every document submitted against it.</p>
      </div>

      <RequirementManagementPanel tenantSlug={tenantSlug} requirements={requirements} statusFilter={statusFilter} createAction={createVendorComplianceRequirementDraftAction.bind(null, tenantSlug)} />
    </div>
  );
}
