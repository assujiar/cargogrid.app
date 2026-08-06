import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { listVendorAssessmentTemplates, VendorAssessmentQueryError } from "../../../../../../server/queries/vendor-assessment.ts";
import type { VendorAssessmentTemplateStatus } from "../../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { TemplateManagementPanel } from "./template-management-panel.tsx";
import { createVendorAssessmentTemplateDraftAction } from "./actions.ts";

/**
 * Vendor Assessment template management (PRC-252, CG-S11-PRC-003) --
 * draft/publish/archive templates and their criteria. Procurement/compliance admin
 * only in practice: the create/publish/archive RPCs themselves gate on PRC:Create/
 * Edit/Approve, so an ordinary assessor can view this screen but every mutating
 * control will surface insufficient_authority if attempted (server-enforced, not
 * merely hidden).
 */
export default async function VendorAssessmentTemplatesPage({
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
  const statusFilter = (status && status.length > 0 ? (status as VendorAssessmentTemplateStatus) : null) ?? null;

  let loadFailed = false;
  let templates: Awaited<ReturnType<typeof listVendorAssessmentTemplates>> = [];
  try {
    templates = await listVendorAssessmentTemplates(supabase, access.tenant.id, access.authUserId, { statusFilter, limit: 100 });
  } catch (error) {
    if (!(error instanceof VendorAssessmentQueryError) && !(error instanceof Error)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading assessment templates. Please try again." />;
  }

  return (
    <div className="flex flex-col gap-4">
      <div>
        <h1 className="text-xl font-semibold text-neutral-900">Assessment templates</h1>
        <p className="text-xs text-neutral-500">Versioned draft → published → archived scoring templates. Weights are validated to sum correctly only at publish.</p>
      </div>

      <TemplateManagementPanel tenantSlug={tenantSlug} templates={templates} statusFilter={statusFilter} createAction={createVendorAssessmentTemplateDraftAction.bind(null, tenantSlug)} />
    </div>
  );
}
