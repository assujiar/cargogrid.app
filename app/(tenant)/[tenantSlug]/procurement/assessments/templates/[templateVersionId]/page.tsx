import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { getVendorAssessmentTemplate, listVendorAssessmentTemplateCriteria, listVendorAssessmentTemplates, VendorAssessmentQueryError } from "../../../../../../../server/queries/vendor-assessment.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { TemplateDetailPanel } from "./template-detail-panel.tsx";
import {
  updateVendorAssessmentTemplateDraftAction,
  addVendorAssessmentTemplateCriterionAction,
  removeVendorAssessmentTemplateCriterionAction,
  publishVendorAssessmentTemplateAction,
  archiveVendorAssessmentTemplateAction,
} from "../actions.ts";

/**
 * Vendor Assessment template detail page (PRC-252, CG-S11-PRC-003): draft-only
 * criteria management (add/remove), publish (with weight-sum validation surfaced
 * server-side), and archive. If a published template already exists for the same
 * (vendor_category, assessment_type), publishing this draft offers to supersede it.
 */
export default async function VendorAssessmentTemplateDetailPage({ params }: { params: Promise<{ tenantSlug: string; templateVersionId: string }> }) {
  const { tenantSlug, templateVersionId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    template: Awaited<ReturnType<typeof getVendorAssessmentTemplate>>;
    criteria: Awaited<ReturnType<typeof listVendorAssessmentTemplateCriteria>>;
    currentPublished: Awaited<ReturnType<typeof listVendorAssessmentTemplates>>;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const template = await getVendorAssessmentTemplate(supabase, templateVersionId, access.authUserId);
    const [criteria, currentPublished] = await Promise.all([
      listVendorAssessmentTemplateCriteria(supabase, templateVersionId, access.authUserId),
      template.status === "draft"
        ? listVendorAssessmentTemplates(supabase, access.tenant.id, access.authUserId, {
            statusFilter: "published",
            vendorCategory: template.vendorCategory,
            assessmentType: template.assessmentType,
            limit: 5,
          })
        : Promise.resolve([]),
    ]);
    loaded = { template, criteria, currentPublished };
  } catch (error) {
    if (!(error instanceof VendorAssessmentQueryError) && !(error instanceof Error)) throw error;
    if (error instanceof VendorAssessmentQueryError && error.message.startsWith("vendor_assessment_template_not_found")) {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this template. Please try again." />;
  }

  const { template, criteria, currentPublished } = loaded;

  return (
    <TemplateDetailPanel
      tenantSlug={tenantSlug}
      template={template}
      criteria={criteria}
      currentPublished={currentPublished.find((t) => t.id !== template.id) ?? null}
      updateDraftAction={updateVendorAssessmentTemplateDraftAction.bind(null, tenantSlug, templateVersionId, template.recordVersion)}
      addCriterionAction={addVendorAssessmentTemplateCriterionAction.bind(null, tenantSlug, templateVersionId)}
      removeCriterionActionFor={(criterionId, expectedVersion) => removeVendorAssessmentTemplateCriterionAction.bind(null, tenantSlug, templateVersionId, criterionId, expectedVersion)}
      publishAction={publishVendorAssessmentTemplateAction.bind(null, tenantSlug, templateVersionId, template.recordVersion)}
      archiveAction={archiveVendorAssessmentTemplateAction.bind(null, tenantSlug, templateVersionId, template.recordVersion)}
    />
  );
}
