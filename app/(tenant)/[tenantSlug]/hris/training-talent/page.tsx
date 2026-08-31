import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listTrainingCompetencies,
  listTrainingCourses,
  listTrainingCourseVersions,
  listTrainingProviders,
  listTrainingSessions,
  listTrainingEnrollments,
  listTrainingCertificates,
  listTrainingDevelopmentPlans,
  listTalentReviewCycles,
  listTalentReviewAssignments,
  listTalentPools,
  listTalentPoolMembers,
  listSuccessionCandidates,
  reportTalentPoolDistributionByDepartment,
  TrainingTalentQueryError,
} from "../../../../../server/queries/training-talent.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { TrainingTalentAdminPanel } from "./training-talent-panel.tsx";
import {
  createTrainingCompetencyAction,
  publishTrainingCompetencyAction,
  createTrainingCourseAction,
  publishTrainingCourseVersionAction,
  addTrainingCourseCompetencyAction,
  addTrainingCoursePrerequisiteAction,
  createTrainingProviderAction,
  createTrainingSessionAction,
  cancelTrainingSessionAction,
  enrollEmployeeInTrainingSessionAction,
  bulkAssignMandatoryTrainingSessionAction,
  decideTrainingEnrollmentAction,
  recordTrainingAttendanceByIdAction,
  recordTrainingCompletionByIdAction,
  recordTrainingAssessmentByIdAction,
  issueTrainingCertificateAction,
  importHistoricalTrainingCertificateAction,
  attachTrainingCertificateEvidenceAction,
  attachTrainingProviderEvidenceAction,
  verifyTrainingCertificateAction,
  revokeTrainingCertificateAction,
  runTrainingCertificateExpiryBatchAction,
  runTrainingCertificateExpiryReminderBatchAction,
  createTrainingDevelopmentPlanAction,
  addTrainingDevelopmentPlanActionAction,
  createTalentReviewCycleAction,
  transitionTalentReviewCycleStatusAction,
  assignTalentReviewerAction,
  reassignTalentReviewerAction,
  createTalentPoolAction,
  addTalentPoolMemberAction,
  removeTalentPoolMemberAction,
  proposeSuccessionCandidateAction,
  decideSuccessionCandidateAction,
} from "./actions.ts";

/**
 * HR/manager/talent-admin Training and Talent workspace (HRT-284,
 * CG-S12-HRT-012): catalogue authoring (competency/course/version/
 * provider/prerequisite), session scheduling and the enrollment-approval
 * queue, attendance/completion/assessment recording, certificate
 * issue/verify/revoke and the durable expiry/reminder batches, development
 * plan authoring, and the RESTRICTED talent review/pool/succession
 * workspace. Every section renders unconditionally -- authorization is
 * enforced server-side by each RPC (HRS:Edit/Approve/Override, or a
 * structural self-decision/assigned-reviewer check), never merely hidden
 * in this page (AGENTS.md "UI visibility is not authorization"): an actor
 * with no HRS:Override simply gets an empty talent section (the RPCs
 * return zero rows / reject writes), not a client-side redirect.
 */
export default async function TrainingTalentAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let competencies: Awaited<ReturnType<typeof listTrainingCompetencies>> = [];
  let courses: Awaited<ReturnType<typeof listTrainingCourses>> = [];
  let providers: Awaited<ReturnType<typeof listTrainingProviders>> = [];
  let sessions: Awaited<ReturnType<typeof listTrainingSessions>> = [];
  let enrollments: Awaited<ReturnType<typeof listTrainingEnrollments>> = [];
  let certificates: Awaited<ReturnType<typeof listTrainingCertificates>> = [];
  let developmentPlans: Awaited<ReturnType<typeof listTrainingDevelopmentPlans>> = [];
  let talentPools: Awaited<ReturnType<typeof listTalentPools>> = [];
  let successionCandidates: Awaited<ReturnType<typeof listSuccessionCandidates>> = [];

  try {
    [competencies, courses, providers, sessions, enrollments, certificates, developmentPlans] = await Promise.all([
      listTrainingCompetencies(supabase, access.tenant.id, access.authUserId),
      listTrainingCourses(supabase, access.tenant.id, access.authUserId),
      listTrainingProviders(supabase, access.tenant.id, access.authUserId),
      listTrainingSessions(supabase, access.tenant.id, access.authUserId),
      listTrainingEnrollments(supabase, access.tenant.id, access.authUserId, null, null, "pending_approval"),
      listTrainingCertificates(supabase, access.tenant.id, access.authUserId),
      listTrainingDevelopmentPlans(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof TrainingTalentQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the training and talent workspace. Please try again." />;
  }

  const courseVersionsByCourseId = Object.fromEntries(
    await Promise.all(courses.map(async (c) => [c.id, await listTrainingCourseVersions(supabase, c.id, access.authUserId)] as const)),
  );

  // The restricted talent workspace: HRS:Override-only reads legitimately
  // return zero rows (or reject) for a non-Override HR/manager actor --
  // that is the intended, disclosed shape, never a page load failure.
  let talentCycles: Awaited<ReturnType<typeof listTalentReviewCycles>> = [];
  try {
    talentCycles = await listTalentReviewCycles(supabase, access.tenant.id, access.authUserId);
  } catch {
    talentCycles = [];
  }
  let talentAssignments: Awaited<ReturnType<typeof listTalentReviewAssignments>> = [];
  try {
    talentAssignments = await listTalentReviewAssignments(supabase, access.tenant.id, access.authUserId);
  } catch {
    talentAssignments = [];
  }
  try {
    talentPools = await listTalentPools(supabase, access.tenant.id, access.authUserId);
  } catch {
    talentPools = [];
  }
  try {
    successionCandidates = await listSuccessionCandidates(supabase, access.tenant.id, access.authUserId);
  } catch {
    successionCandidates = [];
  }

  const poolMembersByPoolId = Object.fromEntries(
    await Promise.all(
      talentPools.map(async (p) => {
        try {
          return [p.id, await listTalentPoolMembers(supabase, p.id, access.authUserId)] as const;
        } catch {
          return [p.id, []] as const;
        }
      }),
    ),
  );

  let distributionByPoolId: Record<string, Awaited<ReturnType<typeof reportTalentPoolDistributionByDepartment>>> = {};
  try {
    distributionByPoolId = Object.fromEntries(
      await Promise.all(talentPools.map(async (p) => [p.id, await reportTalentPoolDistributionByDepartment(supabase, access.tenant.id, p.id, access.authUserId, access.authUserId)] as const)),
    );
  } catch {
    distributionByPoolId = {};
  }

  return (
    <TrainingTalentAdminPanel
      competencies={competencies}
      courses={courses}
      courseVersionsByCourseId={courseVersionsByCourseId}
      providers={providers}
      sessions={sessions}
      pendingEnrollments={enrollments}
      certificates={certificates}
      developmentPlans={developmentPlans}
      talentCycles={talentCycles}
      talentAssignments={talentAssignments}
      talentPools={talentPools}
      poolMembersByPoolId={poolMembersByPoolId}
      distributionByPoolId={distributionByPoolId}
      successionCandidates={successionCandidates}
      createCompetencyAction={createTrainingCompetencyAction.bind(null, tenantSlug)}
      publishCompetencyAction={(competencyId: string, expectedVersion: number) => publishTrainingCompetencyAction.bind(null, tenantSlug, competencyId, expectedVersion)}
      createCourseAction={createTrainingCourseAction.bind(null, tenantSlug)}
      publishCourseVersionAction={(versionId: string, expectedVersion: number) => publishTrainingCourseVersionAction.bind(null, tenantSlug, versionId, expectedVersion)}
      addCourseCompetencyAction={(courseId: string) => addTrainingCourseCompetencyAction.bind(null, tenantSlug, courseId)}
      addPrerequisiteAction={(courseId: string) => addTrainingCoursePrerequisiteAction.bind(null, tenantSlug, courseId)}
      createProviderAction={createTrainingProviderAction.bind(null, tenantSlug)}
      createSessionAction={createTrainingSessionAction.bind(null, tenantSlug)}
      cancelSessionAction={(sessionId: string, expectedVersion: number) => cancelTrainingSessionAction.bind(null, tenantSlug, sessionId, expectedVersion)}
      enrollEmployeeAction={(sessionId: string) => enrollEmployeeInTrainingSessionAction.bind(null, tenantSlug, sessionId)}
      bulkAssignMandatoryAction={(sessionId: string) => bulkAssignMandatoryTrainingSessionAction.bind(null, tenantSlug, sessionId)}
      decideEnrollmentAction={(enrollmentId: string, expectedVersion: number, decision: "approve" | "reject") => decideTrainingEnrollmentAction.bind(null, tenantSlug, enrollmentId, expectedVersion, decision)}
      recordAttendanceAction={recordTrainingAttendanceByIdAction.bind(null, tenantSlug)}
      recordCompletionAction={recordTrainingCompletionByIdAction.bind(null, tenantSlug)}
      recordAssessmentAction={recordTrainingAssessmentByIdAction.bind(null, tenantSlug)}
      issueCertificateAction={issueTrainingCertificateAction.bind(null, tenantSlug)}
      importCertificateAction={importHistoricalTrainingCertificateAction.bind(null, tenantSlug)}
      attachCertificateEvidenceAction={(certificateId: string, expectedVersion: number) => attachTrainingCertificateEvidenceAction.bind(null, tenantSlug, certificateId, expectedVersion)}
      attachProviderEvidenceAction={(providerId: string, expectedVersion: number) => attachTrainingProviderEvidenceAction.bind(null, tenantSlug, providerId, expectedVersion)}
      verifyCertificateAction={(certificateId: string, expectedVersion: number) => verifyTrainingCertificateAction.bind(null, tenantSlug, certificateId, expectedVersion)}
      revokeCertificateAction={(certificateId: string, expectedVersion: number) => revokeTrainingCertificateAction.bind(null, tenantSlug, certificateId, expectedVersion)}
      runExpiryBatchAction={runTrainingCertificateExpiryBatchAction.bind(null, tenantSlug)}
      runReminderBatchAction={runTrainingCertificateExpiryReminderBatchAction.bind(null, tenantSlug)}
      createDevelopmentPlanAction={createTrainingDevelopmentPlanAction.bind(null, tenantSlug)}
      addPlanActionAction={(planId: string) => addTrainingDevelopmentPlanActionAction.bind(null, tenantSlug, planId)}
      createTalentReviewCycleAction={createTalentReviewCycleAction.bind(null, tenantSlug)}
      transitionCycleStatusAction={(cycleId: string, expectedVersion: number, targetStatus: string) => transitionTalentReviewCycleStatusAction.bind(null, tenantSlug, cycleId, expectedVersion, targetStatus)}
      assignReviewerAction={(cycleId: string) => assignTalentReviewerAction.bind(null, tenantSlug, cycleId)}
      reassignReviewerAction={(assignmentId: string) => reassignTalentReviewerAction.bind(null, tenantSlug, assignmentId)}
      createTalentPoolAction={createTalentPoolAction.bind(null, tenantSlug)}
      addPoolMemberAction={(poolId: string) => addTalentPoolMemberAction.bind(null, tenantSlug, poolId)}
      removePoolMemberAction={(memberId: string, expectedVersion: number) => removeTalentPoolMemberAction.bind(null, tenantSlug, memberId, expectedVersion)}
      proposeSuccessionCandidateAction={proposeSuccessionCandidateAction.bind(null, tenantSlug)}
      decideSuccessionCandidateAction={(candidateId: string, expectedVersion: number, decision: "confirm" | "withdraw") => decideSuccessionCandidateAction.bind(null, tenantSlug, candidateId, expectedVersion, decision)}
    />
  );
}
