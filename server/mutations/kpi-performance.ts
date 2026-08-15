/**
 * KPI and Performance mutation primitives (HRT-283, CG-S12-HRT-011). Thin,
 * typed wrappers around every write RPC in
 * supabase/migrations/20260731030000_create_hris_kpi_performance.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parsePerformanceKpiDefinitionRow,
  parsePerformanceKpiDefinitionVersionRow,
  parsePerformanceTemplateRow,
  parsePerformanceTemplateKpiItemRow,
  parsePerformanceCycleRow,
  parsePerformanceGoalAssignmentRow,
  parsePerformanceGoalProgressEntryRow,
  parsePerformanceReviewerAssignmentRow,
  parsePerformanceAssessmentRow,
  parsePerformanceAssessmentKpiScoreRow,
  parsePerformanceOutcomeDetailRow,
  parsePerformanceAppealRow,
  type PerformanceKpiDefinitionRow,
  type PerformanceKpiDefinitionVersionRow,
  type PerformanceTemplateRow,
  type PerformanceTemplateKpiItemRow,
  type PerformanceCycleRow,
  type PerformanceGoalAssignmentRow,
  type PerformanceGoalProgressEntryRow,
  type PerformanceReviewerAssignmentRow,
  type PerformanceAssessmentRow,
  type PerformanceAssessmentKpiScoreRow,
  type PerformanceOutcomeDetailRow,
  type PerformanceAppealRow,
} from "../contracts/kpi-performance/kpi-performance.ts";

export type PerformanceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PERFORMANCE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority", "insufficient_privilege", "stale_version", "reason_required",
  "performance_kpi_definition_not_found", "performance_kpi_definition_code_conflict", "invalid_unit_of_measure",
  "performance_kpi_definition_version_conflict", "invalid_scoring_method", "invalid_target_direction", "target_direction_not_applicable",
  "invalid_transition",
  "performance_template_not_found", "performance_template_code_conflict", "template_not_draft", "invalid_weight",
  "performance_template_kpi_item_conflict", "template_has_no_items", "template_weights_incomplete",
  "performance_cycle_not_found", "performance_cycle_code_conflict", "template_not_published", "invalid_period_range",
  "employee_not_active", "employee_not_found", "kpi_version_not_found", "target_value_required", "invalid_cycle_stage",
  "goals_locked", "goal_assignment_conflict", "performance_goal_assignment_not_found", "goal_not_scoreable",
  "evidence_file_not_found", "evidence_file_not_clean",
  "invalid_role", "invalid_assignee", "manager_assignment_exists", "reviewer_assignment_conflict",
  "performance_reviewer_assignment_not_found",
  "performance_assessment_not_found", "rationale_required", "goal_weights_incomplete", "goal_scores_incomplete",
  "not_a_manager_assessment", "not_a_reviewer_assessment",
  "performance_outcome_not_found", "self_calibration_not_permitted", "invalid_adjusted_score",
  "manager_assessment_missing", "invalid_agreement",
  "performance_appeal_not_found", "self_approval_not_permitted", "invalid_decision",
  "outcome_not_writable",
  // HRT-294 (CG-S12-HRT-022, ISS-2026-114): raised by
  // app.archive_performance_kpi_definition_version since its own creation
  // migration, never added here (API-parity gap).
  "performance_kpi_definition_version_not_found",
] as const;
export type PerformanceKnownMutationErrorCode = (typeof PERFORMANCE_KNOWN_MUTATION_ERROR_CODES)[number];

export class PerformanceMutationError extends Error {
  readonly code: PerformanceKnownMutationErrorCode | "unknown";
  constructor(message: string) {
    super(message);
    this.name = "PerformanceMutationError";
    const prefix = message.split(":")[0]?.trim() ?? "";
    this.code = (PERFORMANCE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)
      ? (prefix as PerformanceKnownMutationErrorCode)
      : "unknown";
  }
}

function unwrap<T>(data: T, error: { message: string } | null): T {
  if (error) throw new PerformanceMutationError(error.message);
  return data;
}

// --- KPI library ---

export async function createPerformanceKpiDefinition(
  client: PerformanceMutationRpcClient,
  input: { tenantId: string; code: string; name: string; description: string | null; unitOfMeasure: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceKpiDefinitionRow> {
  const { data, error } = await client.rpc("create_performance_kpi_definition", {
    p_tenant_id: input.tenantId, p_code: input.code, p_name: input.name, p_description: input.description, p_unit_of_measure: input.unitOfMeasure,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceKpiDefinitionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function createPerformanceKpiDefinitionVersion(
  client: PerformanceMutationRpcClient,
  input: { kpiDefinitionId: string; scoringMethod: string; targetDirection: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceKpiDefinitionVersionRow> {
  const { data, error } = await client.rpc("create_performance_kpi_definition_version", {
    p_kpi_definition_id: input.kpiDefinitionId, p_scoring_method: input.scoringMethod, p_target_direction: input.targetDirection,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceKpiDefinitionVersionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function archivePerformanceKpiDefinitionVersion(
  client: PerformanceMutationRpcClient, input: { versionId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceKpiDefinitionVersionRow> {
  const { data, error } = await client.rpc("archive_performance_kpi_definition_version", {
    p_version_id: input.versionId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceKpiDefinitionVersionRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Template ---

export async function createPerformanceTemplate(
  client: PerformanceMutationRpcClient,
  input: { tenantId: string; code: string; name: string; weightTotalRequired: number; requiresReviewerStage: boolean; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceTemplateRow> {
  const { data, error } = await client.rpc("create_performance_template", {
    p_tenant_id: input.tenantId, p_code: input.code, p_name: input.name, p_weight_total_required: input.weightTotalRequired,
    p_requires_reviewer_stage: input.requiresReviewerStage, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceTemplateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function addPerformanceTemplateKpiItem(
  client: PerformanceMutationRpcClient,
  input: { templateId: string; kpiDefinitionId: string; defaultWeight: number; isRequired: boolean; sortOrder: number; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceTemplateKpiItemRow> {
  const { data, error } = await client.rpc("add_performance_template_kpi_item", {
    p_template_id: input.templateId, p_kpi_definition_id: input.kpiDefinitionId, p_default_weight: input.defaultWeight,
    p_is_required: input.isRequired, p_sort_order: input.sortOrder, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceTemplateKpiItemRow(unwrap(data, error) as Record<string, unknown>);
}

export async function publishPerformanceTemplate(
  client: PerformanceMutationRpcClient, input: { templateId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceTemplateRow> {
  const { data, error } = await client.rpc("publish_performance_template", {
    p_template_id: input.templateId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceTemplateRow(unwrap(data, error) as Record<string, unknown>);
}

export async function archivePerformanceTemplate(
  client: PerformanceMutationRpcClient, input: { templateId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceTemplateRow> {
  const { data, error } = await client.rpc("archive_performance_template", {
    p_template_id: input.templateId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceTemplateRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Cycle ---

export async function createPerformanceCycle(
  client: PerformanceMutationRpcClient,
  input: {
    tenantId: string; templateId: string; code: string; name: string; cycleType: string; periodStart: string; periodEnd: string;
    goalSettingDue: string | null; selfAssessmentDue: string | null; managerAssessmentDue: string | null; calibrationDue: string | null;
    actorAuthUserId: string; actorLabel: string;
  },
): Promise<PerformanceCycleRow> {
  const { data, error } = await client.rpc("create_performance_cycle", {
    p_tenant_id: input.tenantId, p_template_id: input.templateId, p_code: input.code, p_name: input.name, p_cycle_type: input.cycleType,
    p_period_start: input.periodStart, p_period_end: input.periodEnd, p_goal_setting_due: input.goalSettingDue, p_self_assessment_due: input.selfAssessmentDue,
    p_manager_assessment_due: input.managerAssessmentDue, p_calibration_due: input.calibrationDue,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceCycleRow(unwrap(data, error) as Record<string, unknown>);
}

export async function advancePerformanceCycleStage(
  client: PerformanceMutationRpcClient, input: { cycleId: string; expectedVersion: number; targetStatus: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceCycleRow> {
  const { data, error } = await client.rpc("advance_performance_cycle_stage", {
    p_cycle_id: input.cycleId, p_expected_version: input.expectedVersion, p_target_status: input.targetStatus,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceCycleRow(unwrap(data, error) as Record<string, unknown>);
}

export async function cancelPerformanceCycle(
  client: PerformanceMutationRpcClient, input: { cycleId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceCycleRow> {
  const { data, error } = await client.rpc("cancel_performance_cycle", {
    p_cycle_id: input.cycleId, p_expected_version: input.expectedVersion, p_reason: input.reason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceCycleRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Goal assignment ---

export async function assignPerformanceGoal(
  client: PerformanceMutationRpcClient,
  input: {
    cycleId: string; employeeId: string; kpiDefinitionId: string; weight: number; targetValue: number | null; targetUnit: string | null;
    actorAuthUserId: string; actorLabel: string;
  },
): Promise<PerformanceGoalAssignmentRow> {
  const { data, error } = await client.rpc("assign_performance_goal", {
    p_cycle_id: input.cycleId, p_employee_id: input.employeeId, p_kpi_definition_id: input.kpiDefinitionId, p_weight: input.weight,
    p_target_value: input.targetValue, p_target_unit: input.targetUnit, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceGoalAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function markPerformanceGoalNotApplicable(
  client: PerformanceMutationRpcClient, input: { goalAssignmentId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceGoalAssignmentRow> {
  const { data, error } = await client.rpc("mark_performance_goal_not_applicable", {
    p_goal_assignment_id: input.goalAssignmentId, p_expected_version: input.expectedVersion, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceGoalAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function recordPerformanceGoalProgress(
  client: PerformanceMutationRpcClient,
  input: { goalAssignmentId: string; actualValue: number | null; note: string | null; evidenceFileId: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceGoalProgressEntryRow> {
  const { data, error } = await client.rpc("record_performance_goal_progress", {
    p_goal_assignment_id: input.goalAssignmentId, p_actual_value: input.actualValue, p_note: input.note, p_evidence_file_id: input.evidenceFileId,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceGoalProgressEntryRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Reviewer assignment ---

export async function assignPerformanceReviewer(
  client: PerformanceMutationRpcClient,
  input: { cycleId: string; employeeId: string; role: string; assignedToEmployeeId: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceReviewerAssignmentRow> {
  const { data, error } = await client.rpc("assign_performance_reviewer", {
    p_cycle_id: input.cycleId, p_employee_id: input.employeeId, p_role: input.role, p_assigned_to_employee_id: input.assignedToEmployeeId,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceReviewerAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function reassignPerformanceReviewerAssignment(
  client: PerformanceMutationRpcClient,
  input: { assignmentId: string; newAssignedToEmployeeId: string; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceReviewerAssignmentRow> {
  const { data, error } = await client.rpc("reassign_performance_reviewer_assignment", {
    p_assignment_id: input.assignmentId, p_new_assigned_to_employee_id: input.newAssignedToEmployeeId, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceReviewerAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Assessment ---

export async function upsertPerformanceAssessmentKpiScore(
  client: PerformanceMutationRpcClient,
  input: {
    assessmentId: string; goalAssignmentId: string; actualValue: number | null; manualScore: number | null; scoreRationale: string;
    actorAuthUserId: string; actorLabel: string;
  },
): Promise<PerformanceAssessmentKpiScoreRow> {
  const { data, error } = await client.rpc("upsert_performance_assessment_kpi_score", {
    p_assessment_id: input.assessmentId, p_goal_assignment_id: input.goalAssignmentId, p_actual_value: input.actualValue, p_manual_score: input.manualScore,
    p_score_rationale: input.scoreRationale, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceAssessmentKpiScoreRow(unwrap(data, error) as Record<string, unknown>);
}

export async function submitPerformanceSelfAssessment(
  client: PerformanceMutationRpcClient, input: { cycleId: string; expectedVersion: number; overallComment: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceAssessmentRow> {
  const { data, error } = await client.rpc("submit_performance_self_assessment", {
    p_cycle_id: input.cycleId, p_expected_version: input.expectedVersion, p_overall_comment: input.overallComment,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceAssessmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function submitPerformanceManagerAssessment(
  client: PerformanceMutationRpcClient, input: { assessmentId: string; expectedVersion: number; overallComment: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceAssessmentRow> {
  const { data, error } = await client.rpc("submit_performance_manager_assessment", {
    p_assessment_id: input.assessmentId, p_expected_version: input.expectedVersion, p_overall_comment: input.overallComment,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceAssessmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function submitPerformanceReviewerAssessment(
  client: PerformanceMutationRpcClient, input: { assessmentId: string; expectedVersion: number; overallComment: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceAssessmentRow> {
  const { data, error } = await client.rpc("submit_performance_reviewer_assessment", {
    p_assessment_id: input.assessmentId, p_expected_version: input.expectedVersion, p_overall_comment: input.overallComment,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceAssessmentRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Outcome / calibration / appeal ---

export async function calibratePerformanceOutcomeScore(
  client: PerformanceMutationRpcClient,
  input: { outcomeId: string; expectedVersion: number; adjustedScore: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceOutcomeDetailRow> {
  const { data, error } = await client.rpc("calibrate_performance_outcome_score", {
    p_outcome_id: input.outcomeId, p_expected_version: input.expectedVersion, p_adjusted_score: input.adjustedScore, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceOutcomeDetailRow(unwrap(data, error) as Record<string, unknown>);
}

export async function publishPerformanceOutcome(
  client: PerformanceMutationRpcClient, input: { outcomeId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceOutcomeDetailRow> {
  const { data, error } = await client.rpc("publish_performance_outcome", {
    p_outcome_id: input.outcomeId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceOutcomeDetailRow(unwrap(data, error) as Record<string, unknown>);
}

export async function acknowledgePerformanceOutcome(
  client: PerformanceMutationRpcClient,
  input: { outcomeId: string; expectedVersion: number; agreement: "agree" | "disagree"; comment: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceOutcomeDetailRow> {
  const { data, error } = await client.rpc("acknowledge_performance_outcome", {
    p_outcome_id: input.outcomeId, p_expected_version: input.expectedVersion, p_agreement: input.agreement, p_comment: input.comment,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceOutcomeDetailRow(unwrap(data, error) as Record<string, unknown>);
}

export async function submitPerformanceAppeal(
  client: PerformanceMutationRpcClient, input: { outcomeId: string; appealReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceAppealRow> {
  const { data, error } = await client.rpc("submit_performance_appeal", {
    p_outcome_id: input.outcomeId, p_appeal_reason: input.appealReason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceAppealRow(unwrap(data, error) as Record<string, unknown>);
}

export async function decidePerformanceAppeal(
  client: PerformanceMutationRpcClient,
  input: { appealId: string; expectedVersion: number; decision: "uphold" | "overturn"; decisionReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PerformanceAppealRow> {
  const { data, error } = await client.rpc("decide_performance_appeal", {
    p_appeal_id: input.appealId, p_expected_version: input.expectedVersion, p_decision: input.decision, p_decision_reason: input.decisionReason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePerformanceAppealRow(unwrap(data, error) as Record<string, unknown>);
}
