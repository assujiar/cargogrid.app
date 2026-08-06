import { notFound } from "next/navigation";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  getVendorAssessment,
  getVendorAssessmentTemplate,
  listVendorAssessmentTemplateCriteria,
  getVendorAssessmentScoreBreakdown,
  listVendorAssessmentFindings,
  listVendorAssessmentCorrectiveActions,
  listVendorAssessmentTemplates,
  VendorAssessmentQueryError,
} from "../../../../../../server/queries/vendor-assessment.ts";
import { getVendorProfile } from "../../../../../../server/queries/vendor-profile.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { AssessmentDetailPanel } from "./assessment-detail-panel.tsx";
import {
  recordVendorAssessmentAnswerAction,
  calculateVendorAssessmentScoreAction,
  submitVendorAssessmentForReviewAction,
  beginVendorAssessmentReviewAction,
  decideVendorAssessmentReviewAction,
  adjustVendorAssessmentScoreAction,
  closeVendorAssessmentAction,
  startVendorAssessmentReassessmentAction,
  raiseVendorAssessmentFindingAction,
  decideVendorAssessmentFindingAction,
  createVendorAssessmentCorrectiveActionAction,
  updateVendorAssessmentCorrectiveActionStatusAction,
} from "../actions.ts";

/**
 * Vendor Assessment detail page (PRC-252, CG-S11-PRC-003): guided questionnaire
 * (answer criteria, attach evidence, see running score), a score-explanation panel
 * (app.get_vendor_assessment_score_breakdown -- "criterion X contributed Y points"),
 * a findings/corrective-action panel, a review/decide screen (separate reviewer
 * identity, mandatory maker-checker), and a reassessment-due indicator. Every
 * lifecycle action button is rendered only when the current status/actor makes it
 * valid -- authorization is enforced server-side by the RPCs regardless (the same
 * "UI visibility is not authorization" precedent every prior workspace in this
 * repository follows).
 */
export default async function VendorAssessmentDetailPage({ params }: { params: Promise<{ tenantSlug: string; assessmentId: string }> }) {
  const { tenantSlug, assessmentId } = await params;
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  type Loaded = {
    assessment: Awaited<ReturnType<typeof getVendorAssessment>>;
    template: Awaited<ReturnType<typeof getVendorAssessmentTemplate>>;
    criteria: Awaited<ReturnType<typeof listVendorAssessmentTemplateCriteria>>;
    breakdown: Awaited<ReturnType<typeof getVendorAssessmentScoreBreakdown>>;
    findings: Awaited<ReturnType<typeof listVendorAssessmentFindings>>;
    correctiveActions: Awaited<ReturnType<typeof listVendorAssessmentCorrectiveActions>>;
    vendorLegalName: string;
    reassessmentTemplates: Awaited<ReturnType<typeof listVendorAssessmentTemplates>>;
  };

  let loaded: Loaded | null = null;
  let loadFailed = false;
  try {
    const assessment = await getVendorAssessment(supabase, assessmentId, access.authUserId);
    const [template, criteria, breakdown, findings, correctiveActions, vendor, reassessmentTemplates] = await Promise.all([
      getVendorAssessmentTemplate(supabase, assessment.templateVersionId, access.authUserId),
      listVendorAssessmentTemplateCriteria(supabase, assessment.templateVersionId, access.authUserId),
      getVendorAssessmentScoreBreakdown(supabase, assessmentId, access.authUserId),
      listVendorAssessmentFindings(supabase, assessmentId, access.authUserId),
      listVendorAssessmentCorrectiveActions(supabase, assessmentId, access.authUserId),
      getVendorProfile(supabase, assessment.vendorMasterRecordId, access.authUserId),
      assessment.status === "approved" || assessment.status === "closed"
        ? listVendorAssessmentTemplates(supabase, access.tenant.id, access.authUserId, { statusFilter: "published", assessmentType: assessment.assessmentType, limit: 50 })
        : Promise.resolve([]),
    ]);
    loaded = { assessment, template, criteria, breakdown, findings, correctiveActions, vendorLegalName: vendor.legalName, reassessmentTemplates };
  } catch (error) {
    if (!(error instanceof VendorAssessmentQueryError) && !(error instanceof Error)) throw error;
    if (error instanceof VendorAssessmentQueryError && error.message.startsWith("vendor_assessment_not_found")) {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !loaded) {
    return <ErrorState description="Something went wrong loading this assessment. Please try again." />;
  }

  const { assessment, template, criteria, breakdown, findings, correctiveActions, vendorLegalName, reassessmentTemplates } = loaded;

  return (
    <AssessmentDetailPanel
      tenantSlug={tenantSlug}
      viewerAuthUserId={access.authUserId}
      assessment={assessment}
      template={template}
      criteria={criteria}
      breakdown={breakdown}
      findings={findings}
      correctiveActions={correctiveActions}
      vendorLegalName={vendorLegalName}
      reassessmentTemplates={reassessmentTemplates}
      recordAnswerActionFor={(criterionId) => recordVendorAssessmentAnswerAction.bind(null, tenantSlug, assessmentId, criterionId)}
      calculateAction={calculateVendorAssessmentScoreAction.bind(null, tenantSlug, assessmentId, assessment.recordVersion)}
      submitAction={submitVendorAssessmentForReviewAction.bind(null, tenantSlug, assessmentId, assessment.recordVersion)}
      beginReviewAction={beginVendorAssessmentReviewAction.bind(null, tenantSlug, assessmentId, assessment.recordVersion)}
      decideReviewAction={decideVendorAssessmentReviewAction.bind(null, tenantSlug, assessmentId, assessment.recordVersion)}
      adjustScoreAction={adjustVendorAssessmentScoreAction.bind(null, tenantSlug, assessmentId, assessment.recordVersion)}
      closeAction={closeVendorAssessmentAction.bind(null, tenantSlug, assessmentId, assessment.recordVersion)}
      startReassessmentAction={startVendorAssessmentReassessmentAction.bind(null, tenantSlug, assessmentId)}
      raiseFindingAction={raiseVendorAssessmentFindingAction.bind(null, tenantSlug, assessmentId)}
      decideFindingActionFor={(findingId, expectedVersion) => decideVendorAssessmentFindingAction.bind(null, tenantSlug, assessmentId, findingId, expectedVersion)}
      createCorrectiveActionActionFor={(findingId) => createVendorAssessmentCorrectiveActionAction.bind(null, tenantSlug, assessmentId, findingId)}
      updateCorrectiveActionStatusActionFor={(correctiveActionId, expectedVersion) => updateVendorAssessmentCorrectiveActionStatusAction.bind(null, tenantSlug, assessmentId, correctiveActionId, expectedVersion)}
    />
  );
}
