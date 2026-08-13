import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createPerformanceKpiDefinition,
  createPerformanceKpiDefinitionVersion,
  createPerformanceTemplate,
  publishPerformanceTemplate,
  createPerformanceCycle,
  advancePerformanceCycleStage,
  assignPerformanceGoal,
  markPerformanceGoalNotApplicable,
  assignPerformanceReviewer,
  reassignPerformanceReviewerAssignment,
  upsertPerformanceAssessmentKpiScore,
  submitPerformanceSelfAssessment,
  submitPerformanceManagerAssessment,
  calibratePerformanceOutcomeScore,
  publishPerformanceOutcome,
  acknowledgePerformanceOutcome,
  submitPerformanceAppeal,
  decidePerformanceAppeal,
  PerformanceMutationError,
  type PerformanceMutationRpcClient,
} from "./kpi-performance.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: PerformanceMutationRpcClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PerformanceMutationRpcClient;
  return { client, calls };
}

describe("PerformanceMutationError classification", () => {
  test("recognizes a known error-code prefix", () => {
    const err = new PerformanceMutationError("self_calibration_not_permitted: an actor may not calibrate their own outcome");
    assert.equal(err.code, "self_calibration_not_permitted");
  });

  test("falls back to unknown for an unrecognized prefix", () => {
    const err = new PerformanceMutationError("some_other_raw_postgres_error: detail");
    assert.equal(err.code, "unknown");
  });
});

describe("KPI library mutations", () => {
  test("createPerformanceKpiDefinition forwards every field and parses the result", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, code: "sales_target", name: "Sales Target", description: null, unit_of_measure: "currency" }, error: null });
    const row = await createPerformanceKpiDefinition(client, { tenantId: ID_2, code: "sales_target", name: "Sales Target", description: null, unitOfMeasure: "currency", actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.fn, "create_performance_kpi_definition");
    assert.equal(row.code, "sales_target");
  });

  test("createPerformanceKpiDefinitionVersion throws a mapped error on rejection", async () => {
    const { client } = fakeClient({ data: null, error: { message: "invalid_scoring_method: xyz" } });
    await assert.rejects(
      () => createPerformanceKpiDefinitionVersion(client, { kpiDefinitionId: ID_1, scoringMethod: "xyz", targetDirection: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof PerformanceMutationError && err.code === "invalid_scoring_method",
    );
  });
});

describe("Template / cycle mutations", () => {
  test("createPerformanceTemplate forwards weightTotalRequired/requiresReviewerStage", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, code: "annual_std", name: "Annual Standard", status: "draft", weight_total_required: "100.00", requires_reviewer_stage: true, record_version: 1 }, error: null });
    await createPerformanceTemplate(client, { tenantId: ID_2, code: "annual_std", name: "Annual Standard", weightTotalRequired: 100, requiresReviewerStage: true, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_weight_total_required, 100);
    assert.equal(calls[0]?.args.p_requires_reviewer_stage, true);
  });

  test("publishPerformanceTemplate surfaces a template_weights_incomplete rejection", async () => {
    const { client } = fakeClient({ data: null, error: { message: "template_weights_incomplete: default weights sum to 60.00 but 100.00 is required" } });
    await assert.rejects(
      () => publishPerformanceTemplate(client, { templateId: ID_1, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "approver" }),
      (err: unknown) => err instanceof PerformanceMutationError && err.code === "template_weights_incomplete",
    );
  });

  test("createPerformanceCycle forwards every stage-due date", async () => {
    const { client, calls } = fakeClient({
      data: { id: ID_1, template_id: ID_2, code: "fy2026", name: "FY2026", cycle_type: "annual", period_start: "2026-01-01", period_end: "2026-12-31", status: "draft", weight_total_required: "100.00", record_version: 1 },
      error: null,
    });
    await createPerformanceCycle(client, {
      tenantId: ID_2, templateId: ID_1, code: "fy2026", name: "FY2026", cycleType: "annual", periodStart: "2026-01-01", periodEnd: "2026-12-31",
      goalSettingDue: "2026-02-01", selfAssessmentDue: "2026-11-01", managerAssessmentDue: "2026-11-15", calibrationDue: "2026-12-01",
      actorAuthUserId: ACTOR_ID, actorLabel: "hr",
    });
    assert.equal(calls[0]?.args.p_calibration_due, "2026-12-01");
  });

  test("advancePerformanceCycleStage forwards the target status", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, template_id: ID_2, code: "fy2026", name: "FY2026", cycle_type: "annual", period_start: "2026-01-01", period_end: "2026-12-31", status: "goal_setting_open", weight_total_required: "100.00", record_version: 2 }, error: null });
    await advancePerformanceCycleStage(client, { cycleId: ID_1, expectedVersion: 1, targetStatus: "goal_setting_open", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_target_status, "goal_setting_open");
  });
});

describe("Goal assignment mutations", () => {
  test("assignPerformanceGoal forwards weight/target and parses the result", async () => {
    const { client, calls } = fakeClient({
      data: { id: ID_1, employee_id: ID_2, employee_number: null, employee_full_name: null, kpi_definition_id: ID_1, kpi_code: "sales_target", kpi_name: "Sales Target", kpi_version_id: ID_2, weight: "60.00", target_value: "100000.0000", target_unit: "IDR", status: "active", na_reason: null, record_version: 1 },
      error: null,
    });
    const goal = await assignPerformanceGoal(client, { cycleId: ID_1, employeeId: ID_2, kpiDefinitionId: ID_1, weight: 60, targetValue: 100000, targetUnit: "IDR", actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_weight, 60);
    assert.equal(goal.weight, "60.00");
  });

  test("assignPerformanceGoal surfaces a goals_locked rejection after self-assessment submission", async () => {
    const { client } = fakeClient({ data: null, error: { message: "goals_locked: employee's self assessment is already submitted -- goals are frozen" } });
    await assert.rejects(
      () => assignPerformanceGoal(client, { cycleId: ID_1, employeeId: ID_2, kpiDefinitionId: ID_1, weight: 70, targetValue: null, targetUnit: null, actorAuthUserId: ACTOR_ID, actorLabel: "hr" }),
      (err: unknown) => err instanceof PerformanceMutationError && err.code === "goals_locked",
    );
  });

  test("markPerformanceGoalNotApplicable requires and forwards a reason", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, employee_id: ID_2, employee_number: null, employee_full_name: null, kpi_definition_id: ID_1, kpi_code: "x", kpi_name: "X", kpi_version_id: ID_2, weight: "40.00", target_value: null, target_unit: null, status: "not_applicable", na_reason: "role changed", record_version: 2 }, error: null });
    const goal = await markPerformanceGoalNotApplicable(client, { goalAssignmentId: ID_1, expectedVersion: 1, reason: "role changed", actorAuthUserId: ACTOR_ID, actorLabel: "mgr1" });
    assert.equal(calls[0]?.args.p_reason, "role changed");
    assert.equal(goal.naReason, "role changed");
  });
});

describe("Reviewer assignment mutations", () => {
  test("assignPerformanceReviewer forwards role and assignee", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, employee_id: ID_2, employee_full_name: null, role: "reviewer", assigned_to_employee_id: ID_1, assigned_to_full_name: null, status: "active", record_version: 1 }, error: null });
    await assignPerformanceReviewer(client, { cycleId: ID_1, employeeId: ID_2, role: "reviewer", assignedToEmployeeId: ID_1, actorAuthUserId: ACTOR_ID, actorLabel: "hr" });
    assert.equal(calls[0]?.args.p_role, "reviewer");
  });

  test("reassignPerformanceReviewerAssignment requires a reason and returns the NEW assignment", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_2, employee_id: ID_1, employee_full_name: null, role: "manager", assigned_to_employee_id: ID_2, assigned_to_full_name: null, status: "active", record_version: 1 }, error: null });
    const row = await reassignPerformanceReviewerAssignment(client, { assignmentId: ID_1, newAssignedToEmployeeId: ID_2, reason: "org restructuring", actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(calls[0]?.args.p_reason, "org restructuring");
    assert.equal(row.id, ID_2);
  });
});

describe("Assessment mutations", () => {
  test("upsertPerformanceAssessmentKpiScore forwards actual_value/manual_score/rationale", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, goal_assignment_id: ID_2, kpi_code: "x", kpi_name: "X", actual_value: "120000", manual_score: null, raw_score: "100.000", score_rationale: "exceeded target", record_version: 1 }, error: null });
    await upsertPerformanceAssessmentKpiScore(client, { assessmentId: ID_1, goalAssignmentId: ID_2, actualValue: 120000, manualScore: null, scoreRationale: "exceeded target", actorAuthUserId: ACTOR_ID, actorLabel: "mgr1" });
    assert.equal(calls[0]?.args.p_actual_value, 120000);
    assert.equal(calls[0]?.args.p_score_rationale, "exceeded target");
  });

  test("submitPerformanceSelfAssessment surfaces a goal_weights_incomplete rejection", async () => {
    const { client } = fakeClient({ data: null, error: { message: "goal_weights_incomplete: active goal weights sum to 50.00 but 100.00 is required" } });
    await assert.rejects(
      () => submitPerformanceSelfAssessment(client, { cycleId: ID_1, expectedVersion: 1, overallComment: null, actorAuthUserId: ACTOR_ID, actorLabel: "emp2" }),
      (err: unknown) => err instanceof PerformanceMutationError && err.code === "goal_weights_incomplete",
    );
  });

  test("submitPerformanceManagerAssessment forwards the overall comment", async () => {
    const { client, calls } = fakeClient({ data: { id: ID_1, employee_id: ID_2, employee_full_name: null, assessment_type: "manager", assigned_to_employee_id: ID_1, assigned_to_full_name: null, status: "submitted", overall_comment: "strong performer", submitted_at: "2026-11-20T00:00:00Z", record_version: 2 }, error: null });
    const a = await submitPerformanceManagerAssessment(client, { assessmentId: ID_1, expectedVersion: 1, overallComment: "strong performer", actorAuthUserId: ACTOR_ID, actorLabel: "mgr1" });
    assert.equal(calls[0]?.args.p_overall_comment, "strong performer");
    assert.equal(a.overallComment, "strong performer");
  });
});

describe("Outcome / calibration / appeal mutations", () => {
  test("calibratePerformanceOutcomeScore blocks self-calibration (mapped error code)", async () => {
    const { client } = fakeClient({ data: null, error: { message: "self_calibration_not_permitted: an actor may not calibrate their own outcome" } });
    await assert.rejects(
      () => calibratePerformanceOutcomeScore(client, { outcomeId: ID_1, expectedVersion: 1, adjustedScore: 100, reason: "self attempt", actorAuthUserId: ACTOR_ID, actorLabel: "emp1" }),
      (err: unknown) => err instanceof PerformanceMutationError && err.code === "self_calibration_not_permitted",
    );
  });

  test("publishPerformanceOutcome and acknowledgePerformanceOutcome round-trip through the detail parser", async () => {
    const outcomeRow = { id: ID_1, cycle_id: ID_2, employee_id: ID_1, baseline_score: "92.000", calibrated_score: "95.500", final_score: "95.500", score_breakdown: [], status: "published", published_at: "2026-12-01T00:00:00Z", acknowledgement_agreement: null, acknowledgement_comment: null, record_version: 9 };
    const { client: publishClient } = fakeClient({ data: outcomeRow, error: null });
    const published = await publishPerformanceOutcome(publishClient, { outcomeId: ID_1, expectedVersion: 8, actorAuthUserId: ACTOR_ID, actorLabel: "approver" });
    assert.equal(published.status, "published");

    const { client: ackClient, calls } = fakeClient({ data: { ...outcomeRow, status: "acknowledged", acknowledgement_agreement: "agree" }, error: null });
    const acked = await acknowledgePerformanceOutcome(ackClient, { outcomeId: ID_1, expectedVersion: 9, agreement: "agree", comment: "thank you", actorAuthUserId: ACTOR_ID, actorLabel: "emp1" });
    assert.equal(calls[0]?.args.p_agreement, "agree");
    assert.equal(acked.acknowledgementAgreement, "agree");
  });

  test("submitPerformanceAppeal / decidePerformanceAppeal block self-decision (mapped error code)", async () => {
    const { client: submitClient, calls } = fakeClient({ data: { id: ID_1, employee_id: ID_2, employee_full_name: null, outcome_id: ID_1, appeal_reason: "miscalculated", status: "submitted", decision_reason: null, record_version: 1 }, error: null });
    await submitPerformanceAppeal(submitClient, { outcomeId: ID_1, appealReason: "miscalculated", actorAuthUserId: ACTOR_ID, actorLabel: "emp1" });
    assert.equal(calls[0]?.args.p_appeal_reason, "miscalculated");

    const { client: decideClient } = fakeClient({ data: null, error: { message: "self_approval_not_permitted: an actor may not decide their own appeal" } });
    await assert.rejects(
      () => decidePerformanceAppeal(decideClient, { appealId: ID_1, expectedVersion: 1, decision: "overturn", decisionReason: "self decide attempt", actorAuthUserId: ACTOR_ID, actorLabel: "emp1" }),
      (err: unknown) => err instanceof PerformanceMutationError && err.code === "self_approval_not_permitted",
    );
  });
});
