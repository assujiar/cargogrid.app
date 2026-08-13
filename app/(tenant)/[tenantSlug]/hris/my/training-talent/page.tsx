import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  listTrainingSessions,
  listMyTrainingEnrollments,
  listMyTrainingCertificates,
  listMyTrainingDevelopmentPlans,
  listTrainingDevelopmentPlanActions,
  listMyTalentReviewAssignments,
  TrainingTalentQueryError,
} from "../../../../../../server/queries/training-talent.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { MyTrainingTalentPanel } from "./my-training-talent-panel.tsx";
import {
  enrollSelfInTrainingSessionAction,
  cancelMyTrainingEnrollmentAction,
  rescheduleMyTrainingEnrollmentAction,
  updateMyDevelopmentPlanActionStatusAction,
  submitMyTalentReviewAction,
} from "./actions.ts";

/**
 * Employee self-service catalogue browse/enroll/completion/certificate/
 * development-plan view (HRT-284, CG-S12-HRT-012). Also surfaces the
 * employee's own talent-review assignments when they hold one as a
 * reviewer -- "restricted talent reviewers see assigned cases" (section
 * 26) extends to this self-service surface too, never only the admin
 * workspace. Every read here resolves the caller's own employee_id
 * server-side; no employee-id parameter exists on any my_* RPC to spoof.
 */
export default async function MyTrainingTalentPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let sessions: Awaited<ReturnType<typeof listTrainingSessions>> = [];
  let myEnrollments: Awaited<ReturnType<typeof listMyTrainingEnrollments>> = [];
  let myCertificates: Awaited<ReturnType<typeof listMyTrainingCertificates>> = [];
  let myPlans: Awaited<ReturnType<typeof listMyTrainingDevelopmentPlans>> = [];
  let myReviewAssignments: Awaited<ReturnType<typeof listMyTalentReviewAssignments>> = [];

  try {
    [sessions, myEnrollments, myCertificates, myPlans, myReviewAssignments] = await Promise.all([
      listTrainingSessions(supabase, access.tenant.id, access.authUserId, null, "scheduled"),
      listMyTrainingEnrollments(supabase, access.tenant.id, access.authUserId),
      listMyTrainingCertificates(supabase, access.tenant.id, access.authUserId),
      listMyTrainingDevelopmentPlans(supabase, access.tenant.id, access.authUserId),
      listMyTalentReviewAssignments(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof TrainingTalentQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your training and development view. Please try again." />;
  }

  const planActionsByPlanId = Object.fromEntries(
    await Promise.all(myPlans.map(async (p) => [p.id, await listTrainingDevelopmentPlanActions(supabase, p.id, access.authUserId)] as const)),
  );

  return (
    <MyTrainingTalentPanel
      sessions={sessions}
      myEnrollments={myEnrollments}
      myCertificates={myCertificates}
      myPlans={myPlans}
      planActionsByPlanId={planActionsByPlanId}
      myReviewAssignments={myReviewAssignments}
      enrollAction={(sessionId: string) => enrollSelfInTrainingSessionAction.bind(null, tenantSlug, sessionId)}
      cancelEnrollmentAction={(enrollmentId: string, expectedVersion: number) => cancelMyTrainingEnrollmentAction.bind(null, tenantSlug, enrollmentId, expectedVersion)}
      rescheduleEnrollmentAction={(enrollmentId: string) => rescheduleMyTrainingEnrollmentAction.bind(null, tenantSlug, enrollmentId)}
      updateActionStatusAction={(actionId: string, expectedVersion: number) => updateMyDevelopmentPlanActionStatusAction.bind(null, tenantSlug, actionId, expectedVersion)}
      submitReviewAction={(reviewId: string, expectedVersion: number) => submitMyTalentReviewAction.bind(null, tenantSlug, reviewId, expectedVersion)}
    />
  );
}
