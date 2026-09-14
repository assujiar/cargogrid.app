import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import {
  getApplicationDetail,
  getCandidateProfile,
  listApplicationStageHistory,
  listCandidateAssessments,
  listApplicationInterviews,
  getJobOfferForApplication,
  RecruitmentQueryError,
} from "../../../../../../../server/queries/recruitment.ts";
import { ErrorState } from "../../../../../../../components/ui/error-state.tsx";
import { PermissionState } from "../../../../../../../components/ui/permission-state.tsx";
import { ApplicationDetailPanel } from "./application-detail-panel.tsx";
import {
  transitionApplicationStageAction,
  rejectApplicationAction,
  withdrawApplicationAction,
  createCandidateAssessmentAction,
  recordAssessmentResultAction,
  cancelCandidateAssessmentAction,
  scheduleInterviewAction,
  rescheduleInterviewAction,
  cancelInterviewAction,
  completeInterviewAction,
  submitInterviewFeedbackAction,
  createJobOfferVersionAction,
  submitJobOfferForApprovalAction,
  decideJobOfferApprovalAction,
  extendJobOfferAction,
  recordOfferResponseAction,
} from "./actions.ts";

/**
 * Application detail (HRT-276, CG-S12-HRT-004) -- the candidate profile, stage
 * timeline, assessment/interview scorecards, and offer version/timeline all in one
 * page (section 15's "candidate profile", "assessment/interview scorecards", "offer
 * version/timeline" as one bounded application-scoped surface, deliberately not split
 * into four separate route trees for this checkpoint).
 */
export default async function ApplicationDetailPage({ params }: { params: Promise<{ tenantSlug: string; applicationId: string }> }) {
  const { tenantSlug, applicationId } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let denied = false;
  let loadFailed = false;
  let notFoundFlag = false;
  let detail: Awaited<ReturnType<typeof getApplicationDetail>> | null = null;
  let candidate: Awaited<ReturnType<typeof getCandidateProfile>> | null = null;
  let stageHistory: Awaited<ReturnType<typeof listApplicationStageHistory>> = [];
  let assessments: Awaited<ReturnType<typeof listCandidateAssessments>> = [];
  let interviews: Awaited<ReturnType<typeof listApplicationInterviews>> = [];
  let offer: Awaited<ReturnType<typeof getJobOfferForApplication>> = null;

  try {
    detail = await getApplicationDetail(supabase, applicationId, access.authUserId);
    [candidate, stageHistory, assessments, interviews, offer] = await Promise.all([
      getCandidateProfile(supabase, detail.candidateId, access.authUserId),
      listApplicationStageHistory(supabase, applicationId, access.authUserId),
      listCandidateAssessments(supabase, applicationId, access.authUserId),
      listApplicationInterviews(supabase, applicationId, access.authUserId),
      getJobOfferForApplication(supabase, applicationId),
    ]);
  } catch (error) {
    if (!(error instanceof RecruitmentQueryError)) throw error;
    if (error.message.startsWith("insufficient_authority")) denied = true;
    else if (error.message.startsWith("application_not_found")) notFoundFlag = true;
    else loadFailed = true;
  }

  if (notFoundFlag) {
    notFound();
  }
  if (denied) {
    return <PermissionState description="You don't have HR permission to view this application." />;
  }
  if (loadFailed || !detail || !candidate) {
    return <ErrorState description="Something went wrong loading this application. Please try again." />;
  }

  return (
    <ApplicationDetailPanel
      tenantSlug={tenantSlug}
      detail={detail}
      candidate={candidate}
      stageHistory={stageHistory}
      assessments={assessments}
      interviews={interviews}
      offer={
        offer
          ? {
              id: offer.id,
              status: offer.status as never,
              approvalStatus: offer.approvalStatus as never,
              approvalRequestId: offer.approvalRequestId,
              currentVersionId: offer.currentVersionId,
              recordVersion: offer.recordVersion,
            }
          : null
      }
      transitionStageAction={(toStage) => transitionApplicationStageAction.bind(null, tenantSlug, applicationId, detail!.application.recordVersion, toStage)}
      rejectAction={rejectApplicationAction.bind(null, tenantSlug, applicationId, detail.application.recordVersion)}
      withdrawAction={withdrawApplicationAction.bind(null, tenantSlug, applicationId, detail.application.recordVersion)}
      createAssessmentAction={createCandidateAssessmentAction.bind(null, tenantSlug, applicationId)}
      recordAssessmentResultAction={(assessmentId, expectedVersion) => recordAssessmentResultAction.bind(null, tenantSlug, applicationId, assessmentId, expectedVersion)}
      cancelAssessmentAction={(assessmentId, expectedVersion) => cancelCandidateAssessmentAction.bind(null, tenantSlug, applicationId, assessmentId, expectedVersion)}
      scheduleInterviewAction={scheduleInterviewAction.bind(null, tenantSlug, applicationId)}
      rescheduleInterviewAction={(interviewId, expectedVersion) => rescheduleInterviewAction.bind(null, tenantSlug, applicationId, interviewId, expectedVersion)}
      cancelInterviewAction={(interviewId, expectedVersion) => cancelInterviewAction.bind(null, tenantSlug, applicationId, interviewId, expectedVersion)}
      completeInterviewAction={(interviewId, expectedVersion) => completeInterviewAction.bind(null, tenantSlug, applicationId, interviewId, expectedVersion)}
      submitFeedbackAction={(interviewId) => submitInterviewFeedbackAction.bind(null, tenantSlug, applicationId, interviewId)}
      createOfferVersionAction={createJobOfferVersionAction.bind(null, tenantSlug, applicationId)}
      submitOfferForApprovalAction={(offerId, expectedVersion) => submitJobOfferForApprovalAction.bind(null, tenantSlug, applicationId, offerId, expectedVersion)}
      decideOfferApprovalAction={(requestStepId, decision) => decideJobOfferApprovalAction.bind(null, tenantSlug, applicationId, requestStepId, decision)}
      extendOfferAction={(offerId, expectedVersion) => extendJobOfferAction.bind(null, tenantSlug, applicationId, offerId, expectedVersion)}
      recordOfferResponseAction={(offerId, expectedVersion, response) => recordOfferResponseAction.bind(null, tenantSlug, applicationId, offerId, expectedVersion, response)}
    />
  );
}
