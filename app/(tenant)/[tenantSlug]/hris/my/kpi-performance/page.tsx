import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import {
  listMyPerformanceGoalAssignments,
  listMyPerformanceAssessments,
  listPerformanceAssessmentKpiScores,
  listPerformanceGoalProgressEntries,
  listMyPerformanceOutcomes,
  listMyPerformanceAppeals,
  PerformanceQueryError,
} from "../../../../../../server/queries/kpi-performance.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { MyKpiPerformancePanel } from "./my-kpi-performance-panel.tsx";
import {
  recordMyPerformanceGoalProgressAction,
  scoreMyPerformanceGoalAction,
  submitMySelfAssessmentAction,
  acknowledgeMyPerformanceOutcomeAction,
  submitMyPerformanceAppealAction,
} from "./actions.ts";

/**
 * Self-service goal/self-review/outcome view (HRT-283, CG-S12-HRT-011).
 * Every read here resolves the caller's own employee_id server-side via
 * the RPC's own app.get_self_employee call -- no employee-id parameter
 * exists on any of the my_* RPCs this page calls, structurally impossible
 * to spoof.
 */
export default async function MyKpiPerformancePage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let goals: Awaited<ReturnType<typeof listMyPerformanceGoalAssignments>> = [];
  let assessments: Awaited<ReturnType<typeof listMyPerformanceAssessments>> = [];
  let outcomes: Awaited<ReturnType<typeof listMyPerformanceOutcomes>> = [];
  let appeals: Awaited<ReturnType<typeof listMyPerformanceAppeals>> = [];

  try {
    [goals, assessments, outcomes, appeals] = await Promise.all([
      listMyPerformanceGoalAssignments(supabase, access.tenant.id, access.authUserId),
      listMyPerformanceAssessments(supabase, access.tenant.id, access.authUserId, "self"),
      listMyPerformanceOutcomes(supabase, access.tenant.id, access.authUserId),
      listMyPerformanceAppeals(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof PerformanceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading your goals and reviews. Please try again." />;
  }

  const selfAssessment = assessments[0] ?? null;
  const selfScores = selfAssessment ? await listPerformanceAssessmentKpiScores(supabase, selfAssessment.id, access.authUserId) : [];
  const progressByGoalId = Object.fromEntries(
    await Promise.all(goals.map(async (g) => [g.id, await listPerformanceGoalProgressEntries(supabase, g.id, access.authUserId)] as const)),
  );

  return (
    <MyKpiPerformancePanel
      goals={goals}
      selfAssessment={selfAssessment}
      selfScores={selfScores}
      progressByGoalId={progressByGoalId}
      outcomes={outcomes}
      appeals={appeals}
      recordProgressAction={(goalAssignmentId: string) => recordMyPerformanceGoalProgressAction.bind(null, tenantSlug, goalAssignmentId)}
      scoreGoalAction={(assessmentId: string, goalAssignmentId: string) => scoreMyPerformanceGoalAction.bind(null, tenantSlug, assessmentId, goalAssignmentId)}
      submitSelfAssessmentAction={(cycleId: string, expectedVersion: number) => submitMySelfAssessmentAction.bind(null, tenantSlug, cycleId, expectedVersion)}
      acknowledgeOutcomeAction={(outcomeId: string, expectedVersion: number, agreement: "agree" | "disagree") => acknowledgeMyPerformanceOutcomeAction.bind(null, tenantSlug, outcomeId, expectedVersion, agreement)}
      submitAppealAction={(outcomeId: string) => submitMyPerformanceAppealAction.bind(null, tenantSlug, outcomeId)}
    />
  );
}
