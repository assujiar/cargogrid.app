import { notFound } from "next/navigation";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listPerformanceKpiDefinitions,
  listPerformanceTemplates,
  listPerformanceTemplateKpiItems,
  listPerformanceCycles,
  listPerformanceGoalAssignments,
  listMyPerformanceAssessments,
  listPerformanceAssessmentKpiScores,
  listPerformanceOutcomes,
  listPerformanceAppeals,
  reportPerformanceCycleScoreDistribution,
  PerformanceQueryError,
} from "../../../../../server/queries/kpi-performance.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { KpiPerformanceAdminPanel } from "./kpi-performance-panel.tsx";
import {
  createPerformanceKpiDefinitionAction,
  createPerformanceTemplateAction,
  addPerformanceTemplateKpiItemAction,
  publishPerformanceTemplateAction,
  createPerformanceCycleAction,
  advancePerformanceCycleStageAction,
  cancelPerformanceCycleAction,
  assignPerformanceGoalAction,
  markPerformanceGoalNotApplicableAction,
  assignPerformanceReviewerAction,
  reassignPerformanceReviewerAssignmentAction,
  scorePerformanceGoalAction,
  submitPerformanceManagerAssessmentAction,
  submitPerformanceReviewerAssessmentAction,
  calibratePerformanceOutcomeScoreAction,
  publishPerformanceOutcomeAction,
  decidePerformanceAppealAction,
} from "./actions.ts";

/**
 * HR/manager/reviewer KPI and Performance workspace (HRT-283,
 * CG-S12-HRT-011): KPI library + cycle/template builder, manager/reviewer
 * team review, and the calibration grid. Every section renders
 * unconditionally -- authorization is enforced server-side by each RPC
 * (HRS:Edit/Approve/Override, or the assessment's own assigned-actor
 * identity), never merely hidden in this page (AGENTS.md "UI visibility is
 * not authorization").
 *
 * V1 scope boundary (disclosed, build log): goal assignment, team review,
 * calibration, and appeals sections operate on the single MOST RECENT
 * non-cancelled cycle (by period_start). The cycle list/create/advance
 * section itself still shows and manages every cycle regardless.
 */
export default async function KpiPerformanceAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let kpiDefinitions: Awaited<ReturnType<typeof listPerformanceKpiDefinitions>> = [];
  let templates: Awaited<ReturnType<typeof listPerformanceTemplates>> = [];
  let cycles: Awaited<ReturnType<typeof listPerformanceCycles>> = [];
  let myPendingAssessments: Awaited<ReturnType<typeof listMyPerformanceAssessments>> = [];

  try {
    [kpiDefinitions, templates, cycles, myPendingAssessments] = await Promise.all([
      listPerformanceKpiDefinitions(supabase, access.tenant.id, access.authUserId),
      listPerformanceTemplates(supabase, access.tenant.id, access.authUserId),
      listPerformanceCycles(supabase, access.tenant.id, access.authUserId, null),
      listMyPerformanceAssessments(supabase, access.tenant.id, access.authUserId),
    ]);
  } catch (error) {
    if (!(error instanceof PerformanceQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return <ErrorState description="Something went wrong loading the KPI and performance workspace. Please try again." />;
  }

  const templateItemsByTemplateId = Object.fromEntries(
    await Promise.all(templates.map(async (t) => [t.id, await listPerformanceTemplateKpiItems(supabase, t.id, access.authUserId)] as const)),
  );

  const currentCycle = cycles.find((c) => c.status !== "cancelled") ?? null;

  let goalAssignments: Awaited<ReturnType<typeof listPerformanceGoalAssignments>> = [];
  let outcomes: Awaited<ReturnType<typeof listPerformanceOutcomes>> = [];
  let appeals: Awaited<ReturnType<typeof listPerformanceAppeals>> = [];
  let distribution: Awaited<ReturnType<typeof reportPerformanceCycleScoreDistribution>> = [];

  if (currentCycle) {
    [goalAssignments, outcomes, appeals] = await Promise.all([
      listPerformanceGoalAssignments(supabase, access.tenant.id, currentCycle.id, access.authUserId),
      listPerformanceOutcomes(supabase, access.tenant.id, currentCycle.id, access.authUserId),
      listPerformanceAppeals(supabase, access.tenant.id, currentCycle.id, access.authUserId),
    ]);
    // The aggregate k-anonymity-floor report is HRS:View personal data
    // gated -- a manager/reviewer-only actor legitimately gets
    // insufficient_authority here; that is not a page load failure, just
    // an empty section for this actor.
    try {
      distribution = await reportPerformanceCycleScoreDistribution(supabase, access.tenant.id, currentCycle.id, access.authUserId, access.authUserId);
    } catch {
      distribution = [];
    }
  }

  const myManagerReviewerAssessments = myPendingAssessments.filter((a) => a.assessmentType !== "self");
  const scoresByAssessmentId = Object.fromEntries(
    await Promise.all(myManagerReviewerAssessments.map(async (a) => [a.id, await listPerformanceAssessmentKpiScores(supabase, a.id, access.authUserId)] as const)),
  );
  const goalsByEmployeeId = Object.fromEntries(
    currentCycle
      ? await Promise.all(
          [...new Set(myManagerReviewerAssessments.map((a) => a.employeeId))].map(
            async (employeeId) => [employeeId, await listPerformanceGoalAssignments(supabase, access.tenant.id, currentCycle.id, access.authUserId, employeeId)] as const,
          ),
        )
      : [],
  );

  return (
    <KpiPerformanceAdminPanel
      kpiDefinitions={kpiDefinitions}
      templates={templates}
      templateItemsByTemplateId={templateItemsByTemplateId}
      cycles={cycles}
      currentCycle={currentCycle}
      goalAssignments={goalAssignments}
      myManagerReviewerAssessments={myManagerReviewerAssessments}
      scoresByAssessmentId={scoresByAssessmentId}
      goalsByEmployeeId={goalsByEmployeeId}
      outcomes={outcomes}
      appeals={appeals}
      distribution={distribution}
      createPerformanceKpiDefinitionAction={createPerformanceKpiDefinitionAction.bind(null, tenantSlug)}
      createPerformanceTemplateAction={createPerformanceTemplateAction.bind(null, tenantSlug)}
      addPerformanceTemplateKpiItemAction={(templateId: string) => addPerformanceTemplateKpiItemAction.bind(null, tenantSlug, templateId)}
      publishPerformanceTemplateAction={(templateId: string, expectedVersion: number) => publishPerformanceTemplateAction.bind(null, tenantSlug, templateId, expectedVersion)}
      createPerformanceCycleAction={createPerformanceCycleAction.bind(null, tenantSlug)}
      advancePerformanceCycleStageAction={(cycleId: string, expectedVersion: number, targetStatus: string) => advancePerformanceCycleStageAction.bind(null, tenantSlug, cycleId, expectedVersion, targetStatus)}
      cancelPerformanceCycleAction={(cycleId: string, expectedVersion: number) => cancelPerformanceCycleAction.bind(null, tenantSlug, cycleId, expectedVersion)}
      assignPerformanceGoalAction={(cycleId: string) => assignPerformanceGoalAction.bind(null, tenantSlug, cycleId)}
      markPerformanceGoalNotApplicableAction={(goalAssignmentId: string, expectedVersion: number) => markPerformanceGoalNotApplicableAction.bind(null, tenantSlug, goalAssignmentId, expectedVersion)}
      assignPerformanceReviewerAction={(cycleId: string) => assignPerformanceReviewerAction.bind(null, tenantSlug, cycleId)}
      reassignPerformanceReviewerAssignmentAction={(assignmentId: string) => reassignPerformanceReviewerAssignmentAction.bind(null, tenantSlug, assignmentId)}
      scorePerformanceGoalAction={(assessmentId: string, goalAssignmentId: string) => scorePerformanceGoalAction.bind(null, tenantSlug, assessmentId, goalAssignmentId)}
      submitPerformanceManagerAssessmentAction={(assessmentId: string, expectedVersion: number) => submitPerformanceManagerAssessmentAction.bind(null, tenantSlug, assessmentId, expectedVersion)}
      submitPerformanceReviewerAssessmentAction={(assessmentId: string, expectedVersion: number) => submitPerformanceReviewerAssessmentAction.bind(null, tenantSlug, assessmentId, expectedVersion)}
      calibratePerformanceOutcomeScoreAction={(outcomeId: string, expectedVersion: number) => calibratePerformanceOutcomeScoreAction.bind(null, tenantSlug, outcomeId, expectedVersion)}
      publishPerformanceOutcomeAction={(outcomeId: string, expectedVersion: number) => publishPerformanceOutcomeAction.bind(null, tenantSlug, outcomeId, expectedVersion)}
      decidePerformanceAppealAction={(appealId: string, expectedVersion: number, decision: "uphold" | "overturn") => decidePerformanceAppealAction.bind(null, tenantSlug, appealId, expectedVersion, decision)}
    />
  );
}
