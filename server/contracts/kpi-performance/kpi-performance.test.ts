import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parsePerformanceKpiDefinitionRow,
  parsePerformanceKpiDefinitionVersionRow,
  parsePerformanceTemplateRow,
  parsePerformanceTemplateKpiItemRow,
  parsePerformanceCycleRow,
  parsePerformanceGoalAssignmentRow,
  parsePerformanceMyGoalAssignmentRow,
  parsePerformanceGoalProgressEntryRow,
  parsePerformanceReviewerAssignmentRow,
  parsePerformanceAssessmentRow,
  parsePerformanceAssessmentKpiScoreRow,
  parsePerformanceOutcomeRow,
  parsePerformanceOutcomeDetailRow,
  parsePerformanceCalibrationAdjustmentRow,
  parsePerformanceAppealRow,
  parsePerformanceCycleScoreDistributionRow,
} from "./kpi-performance.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";
const ID_3 = "423e4567-e89b-12d3-a456-426614174000";

describe("parsePerformanceKpiDefinitionRow / parsePerformanceKpiDefinitionVersionRow", () => {
  test("maps a target_ratio KPI version with a direction", () => {
    const v = parsePerformanceKpiDefinitionVersionRow({
      id: ID_1, version_number: 2, status: "active", scoring_method: "target_ratio", target_direction: "higher_is_better", record_version: 3,
    });
    assert.equal(v.scoringMethod, "target_ratio");
    assert.equal(v.targetDirection, "higher_is_better");
  });

  test("a qualitative_scale version carries null target_direction", () => {
    const v = parsePerformanceKpiDefinitionVersionRow({
      id: ID_1, version_number: 1, status: "active", scoring_method: "qualitative_scale", target_direction: null, record_version: 1,
    });
    assert.equal(v.targetDirection, null);
  });

  test("maps definition code/name/description/unit", () => {
    const k = parsePerformanceKpiDefinitionRow({ id: ID_1, code: "sales_target", name: "Sales Target", description: null, unit_of_measure: "currency" });
    assert.equal(k.code, "sales_target");
    assert.equal(k.description, null);
  });
});

describe("parsePerformanceTemplateRow / parsePerformanceTemplateKpiItemRow", () => {
  test("weightTotalRequired and default_weight are decimal strings, never JS numbers", () => {
    const t = parsePerformanceTemplateRow({ id: ID_1, code: "annual_std", name: "Annual Standard", status: "draft", weight_total_required: 100.0, requires_reviewer_stage: true, record_version: 1 });
    assert.equal(typeof t.weightTotalRequired, "string");
    assert.equal(t.weightTotalRequired, "100");

    const item = parsePerformanceTemplateKpiItemRow({ id: ID_1, kpi_definition_id: ID_2, kpi_code: "sales_target", kpi_name: "Sales Target", default_weight: "60.00", is_required: true, sort_order: 1 });
    assert.equal(item.defaultWeight, "60.00");
  });
});

describe("parsePerformanceCycleRow", () => {
  test("maps every cycle stage status", () => {
    const c = parsePerformanceCycleRow({
      id: ID_1, template_id: ID_2, code: "fy2026", name: "FY2026", cycle_type: "annual", period_start: "2026-01-01", period_end: "2026-12-31",
      status: "manager_assessment_open", weight_total_required: "100.00", record_version: 4,
    });
    assert.equal(c.status, "manager_assessment_open");
  });
});

describe("parsePerformanceGoalAssignmentRow / parsePerformanceMyGoalAssignmentRow", () => {
  test("not_applicable goal carries a reason", () => {
    const g = parsePerformanceGoalAssignmentRow({
      id: ID_1, employee_id: ID_2, employee_number: "EMP-2026-000001", employee_full_name: "Emp Two", kpi_definition_id: ID_3, kpi_code: "quality_score",
      kpi_name: "Quality Score", kpi_version_id: ID_1, weight: "40.00", target_value: null, target_unit: null, status: "not_applicable",
      na_reason: "role changed mid-cycle", record_version: 2,
    });
    assert.equal(g.status, "not_applicable");
    assert.equal(g.naReason, "role changed mid-cycle");
  });

  test("my-goal-assignment row omits employee columns", () => {
    const g = parsePerformanceMyGoalAssignmentRow({
      id: ID_1, cycle_id: ID_2, kpi_definition_id: ID_3, kpi_code: "sales_target", kpi_name: "Sales Target", kpi_version_id: ID_1,
      weight: "60.00", target_value: "100000.0000", target_unit: "IDR", status: "active", na_reason: null, record_version: 1,
    });
    assert.equal(g.targetValue, "100000.0000");
  });
});

describe("parsePerformanceGoalProgressEntryRow", () => {
  test("maps a progress entry with no evidence file", () => {
    const p = parsePerformanceGoalProgressEntryRow({ id: ID_1, actual_value: "45000", note: "halfway", evidence_file_id: null, recorded_by: "emp1", recorded_at: "2026-06-01T00:00:00Z" });
    assert.equal(p.evidenceFileId, null);
    assert.equal(p.actualValue, "45000");
  });
});

describe("parsePerformanceReviewerAssignmentRow", () => {
  test("maps a manager assignment", () => {
    const r = parsePerformanceReviewerAssignmentRow({
      id: ID_1, employee_id: ID_2, employee_full_name: "Emp One", role: "manager", assigned_to_employee_id: ID_3, assigned_to_full_name: "Mgr One", status: "active", record_version: 1,
    });
    assert.equal(r.role, "manager");
    assert.equal(r.status, "active");
  });
});

describe("parsePerformanceAssessmentRow / parsePerformanceAssessmentKpiScoreRow", () => {
  test("a not-yet-submitted assessment has null submitted_at", () => {
    const a = parsePerformanceAssessmentRow({
      id: ID_1, employee_id: ID_2, employee_full_name: "Emp One", assessment_type: "manager", assigned_to_employee_id: ID_3, assigned_to_full_name: "Mgr One",
      status: "draft", overall_comment: null, submitted_at: null, record_version: 1,
    });
    assert.equal(a.submittedAt, null);
  });

  test("score row: raw_score is always a decimal string, never a JS number", () => {
    const s = parsePerformanceAssessmentKpiScoreRow({
      id: ID_1, goal_assignment_id: ID_2, kpi_code: "sales_target", kpi_name: "Sales Target", actual_value: "120000", manual_score: null,
      raw_score: 100, score_rationale: "exceeded target", record_version: 1,
    });
    assert.equal(typeof s.rawScore, "string");
    assert.equal(s.rawScore, "100");
  });
});

describe("parsePerformanceOutcomeRow / parsePerformanceOutcomeDetailRow", () => {
  test("outcome detail carries an explainable score_breakdown array, never a raw jsonb dump", () => {
    const o = parsePerformanceOutcomeDetailRow({
      id: ID_1, cycle_id: ID_2, employee_id: ID_3, baseline_score: "92.000", calibrated_score: "95.500", final_score: "95.500",
      score_breakdown: [
        { goalAssignmentId: ID_1, kpiDefinitionId: ID_2, weight: "60.00", rawScore: "100.000", weightedContribution: "60.000" },
        { goalAssignmentId: ID_2, kpiDefinitionId: ID_3, weight: "40.00", rawScore: "80.000", weightedContribution: "32.000" },
      ],
      status: "published", published_at: "2026-12-15T00:00:00Z", acknowledgement_agreement: null, acknowledgement_comment: null, record_version: 8,
    });
    assert.equal(o.scoreBreakdown.length, 2);
    assert.equal(o.finalScore, "95.500");
  });

  test("summary outcome row has no score_breakdown field at all", () => {
    const o = parsePerformanceOutcomeRow({
      id: ID_1, employee_id: ID_2, employee_full_name: "Emp One", baseline_score: "92.000", calibrated_score: null, final_score: "92.000",
      status: "draft", published_at: null, acknowledgement_agreement: null, record_version: 1,
    });
    assert.equal(o.status, "draft");
  });
});

describe("parsePerformanceCalibrationAdjustmentRow", () => {
  test("maps a governed calibration adjustment", () => {
    const c = parsePerformanceCalibrationAdjustmentRow({
      id: ID_1, previous_score: "92.000", adjusted_score: "95.500", adjustment_reason: "committee normalization", calibrated_by: "approver", calibrated_at: "2026-12-10T00:00:00Z",
    });
    assert.equal(c.adjustedScore, "95.500");
  });
});

describe("parsePerformanceAppealRow", () => {
  test("maps an appeal with a pending decision", () => {
    const a = parsePerformanceAppealRow({
      id: ID_1, employee_id: ID_2, employee_full_name: "Emp One", outcome_id: ID_3, appeal_reason: "miscalculated", status: "submitted", decision_reason: null, record_version: 1,
    });
    assert.equal(a.decisionReason, null);
  });
});

describe("parsePerformanceCycleScoreDistributionRow", () => {
  test("a suppressed small-cohort row has a null average", () => {
    const r = parsePerformanceCycleScoreDistributionRow({ department_org_unit_id: ID_1, department_name: "Small Dept", employee_count: 2, avg_final_score: null, suppressed: true });
    assert.equal(r.suppressed, true);
    assert.equal(r.avgFinalScore, null);
  });

  test("an unsuppressed cohort reports its real average as a decimal string", () => {
    const r = parsePerformanceCycleScoreDistributionRow({ department_org_unit_id: ID_1, department_name: "Big Dept", employee_count: 5, avg_final_score: 73.0, suppressed: false });
    assert.equal(r.suppressed, false);
    assert.equal(r.avgFinalScore, "73");
  });
});
