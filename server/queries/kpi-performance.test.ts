import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listPerformanceKpiDefinitions,
  listPerformanceTemplates,
  listPerformanceCycles,
  getPerformanceCycle,
  listPerformanceGoalAssignments,
  listMyPerformanceGoalAssignments,
  listPerformanceReviewerAssignments,
  listPerformanceAssessments,
  listMyPerformanceAssessments,
  listPerformanceOutcomes,
  listMyPerformanceOutcomes,
  getPerformanceOutcome,
  listPerformanceCalibrationAdjustments,
  listPerformanceAppeals,
  reportPerformanceCycleScoreDistribution,
  PerformanceQueryError,
  type PerformanceQueryClient,
} from "./kpi-performance.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: PerformanceQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PerformanceQueryClient;
  return { client, calls };
}

describe("listPerformanceKpiDefinitions / listPerformanceTemplates", () => {
  test("listPerformanceKpiDefinitions forwards tenant and actor", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPerformanceKpiDefinitions(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_performance_kpi_definitions");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
  });

  test("listPerformanceTemplates surfaces a mapped query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(() => listPerformanceTemplates(client, TENANT_ID, ACTOR_ID), PerformanceQueryError);
  });
});

describe("listPerformanceCycles / getPerformanceCycle", () => {
  test("getPerformanceCycle returns null on an empty array response (RLS-filtered-to-zero-rows)", async () => {
    const { client } = fakeClient({ data: [], error: null });
    const result = await getPerformanceCycle(client, ID_1, ACTOR_ID);
    assert.equal(result, null);
  });

  test("listPerformanceCycles forwards an optional status filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPerformanceCycles(client, TENANT_ID, ACTOR_ID, "manager_assessment_open");
    assert.equal(calls[0]?.args.p_status, "manager_assessment_open");
  });
});

describe("listPerformanceGoalAssignments / listMyPerformanceGoalAssignments", () => {
  test("listPerformanceGoalAssignments defaults employeeId to null (scoped default, not an explicit self-filter)", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPerformanceGoalAssignments(client, TENANT_ID, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.args.p_employee_id, null);
  });

  test("listMyPerformanceGoalAssignments parses weight as a decimal string", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, cycle_id: ID_2, kpi_definition_id: ID_1, kpi_code: "sales_target", kpi_name: "Sales Target", kpi_version_id: ID_1, weight: "60.00", target_value: null, target_unit: null, status: "active", na_reason: null, record_version: 1 }],
      error: null,
    });
    const rows = await listMyPerformanceGoalAssignments(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows[0]?.weight, "60.00");
  });
});

describe("listPerformanceReviewerAssignments / listPerformanceAssessments / listMyPerformanceAssessments", () => {
  test("listPerformanceAssessments forwards an optional assessment-type filter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPerformanceAssessments(client, TENANT_ID, ID_1, ACTOR_ID, ID_2, "manager");
    assert.equal(calls[0]?.args.p_assessment_type, "manager");
  });

  test("listMyPerformanceAssessments covers self/manager/reviewer uniformly via assigned_to_employee_id = self", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyPerformanceAssessments(client, TENANT_ID, ACTOR_ID, "reviewer");
    assert.equal(calls[0]?.fn, "list_my_performance_assessments");
    assert.equal(calls[0]?.args.p_assessment_type, "reviewer");
  });

  test("listPerformanceReviewerAssignments surfaces a mapped query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(() => listPerformanceReviewerAssignments(client, TENANT_ID, ID_1, ACTOR_ID), PerformanceQueryError);
  });
});

describe("listPerformanceOutcomes / listMyPerformanceOutcomes / getPerformanceOutcome / listPerformanceCalibrationAdjustments", () => {
  test("getPerformanceOutcome parses score_breakdown as a structured array, never a raw string", async () => {
    const { client } = fakeClient({
      data: [{
        id: ID_1, cycle_id: ID_2, employee_id: ID_1, baseline_score: "92.000", calibrated_score: null, final_score: "92.000",
        score_breakdown: [{ goalAssignmentId: ID_1, kpiDefinitionId: ID_2, weight: "60.00", rawScore: "100.000", weightedContribution: "60.000" }],
        status: "draft", published_at: null, acknowledgement_agreement: null, acknowledgement_comment: null, record_version: 1,
      }],
      error: null,
    });
    const outcome = await getPerformanceOutcome(client, ID_1, ACTOR_ID);
    assert.equal(outcome?.scoreBreakdown.length, 1);
  });

  test("listPerformanceCalibrationAdjustments (HR-only read) forwards the outcome id", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPerformanceCalibrationAdjustments(client, ID_1, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_performance_calibration_adjustments");
    assert.equal(calls[0]?.args.p_outcome_id, ID_1);
  });

  test("listMyPerformanceOutcomes surfaces a mapped query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(() => listMyPerformanceOutcomes(client, TENANT_ID, ACTOR_ID), PerformanceQueryError);
  });
});

describe("listPerformanceAppeals / reportPerformanceCycleScoreDistribution", () => {
  test("reportPerformanceCycleScoreDistribution forwards the actor label (audited even as a read)", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await reportPerformanceCycleScoreDistribution(client, TENANT_ID, ID_1, ACTOR_ID, "approver");
    assert.equal(calls[0]?.fn, "report_performance_cycle_score_distribution");
    assert.equal(calls[0]?.args.p_actor_label, "approver");
  });

  test("reportPerformanceCycleScoreDistribution parses a suppressed row cleanly", async () => {
    const { client } = fakeClient({ data: [{ department_org_unit_id: ID_1, department_name: "Small Dept", employee_count: 2, avg_final_score: null, suppressed: true }], error: null });
    const rows = await reportPerformanceCycleScoreDistribution(client, TENANT_ID, ID_1, ACTOR_ID, "approver");
    assert.equal(rows[0]?.suppressed, true);
    assert.equal(rows[0]?.avgFinalScore, null);
  });

  test("listPerformanceAppeals surfaces a mapped query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(() => listPerformanceAppeals(client, TENANT_ID, ID_1, ACTOR_ID), PerformanceQueryError);
  });
});
