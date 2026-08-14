/**
 * KPI and Performance contract (HRT-283, CG-S12-HRT-011). Mirrors
 * supabase/migrations/20260731030000_create_hris_kpi_performance.sql's
 * table shapes and RPCs. Follows the exact directory convention every
 * prior HRT checkpoint established: Zod schemas here, list/read
 * projections in server/queries/kpi-performance.ts, RPC-calling mutation
 * wrappers with an enumerated error-code type in
 * server/mutations/kpi-performance.ts.
 *
 * Every weight/score/target-value field is a decimal STRING once parsed
 * by this contract (Postgres `numeric` -> JS) -- this repository's own
 * established "exact decimals, never binary float" discipline, extended
 * here from money (HRT-282) to performance scores (decision 1: "explainable
 * exact-decimal scoring"). The shared `decimal` schema accepts either a
 * string or number on the wire and unconditionally `String()`-normalizes
 * it on OUTPUT.
 */

import { z } from "zod";

export const PERFORMANCE_UNITS_OF_MEASURE = ["percent", "count", "currency", "ratio", "qualitative"] as const;
export const PerformanceUnitOfMeasureSchema = z.enum(PERFORMANCE_UNITS_OF_MEASURE);
export type PerformanceUnitOfMeasure = z.infer<typeof PerformanceUnitOfMeasureSchema>;

export const PERFORMANCE_KPI_VERSION_STATUSES = ["active", "archived"] as const;
export const PerformanceKpiVersionStatusSchema = z.enum(PERFORMANCE_KPI_VERSION_STATUSES);
export type PerformanceKpiVersionStatus = z.infer<typeof PerformanceKpiVersionStatusSchema>;

export const PERFORMANCE_SCORING_METHODS = ["target_ratio", "milestone_percent", "qualitative_scale"] as const;
export const PerformanceScoringMethodSchema = z.enum(PERFORMANCE_SCORING_METHODS);
export type PerformanceScoringMethod = z.infer<typeof PerformanceScoringMethodSchema>;

export const PERFORMANCE_TARGET_DIRECTIONS = ["higher_is_better", "lower_is_better"] as const;
export const PerformanceTargetDirectionSchema = z.enum(PERFORMANCE_TARGET_DIRECTIONS);
export type PerformanceTargetDirection = z.infer<typeof PerformanceTargetDirectionSchema>;

export const PERFORMANCE_TEMPLATE_STATUSES = ["draft", "published", "archived"] as const;
export const PerformanceTemplateStatusSchema = z.enum(PERFORMANCE_TEMPLATE_STATUSES);
export type PerformanceTemplateStatus = z.infer<typeof PerformanceTemplateStatusSchema>;

export const PERFORMANCE_CYCLE_TYPES = ["annual", "semi_annual", "quarterly", "custom"] as const;
export const PerformanceCycleTypeSchema = z.enum(PERFORMANCE_CYCLE_TYPES);
export type PerformanceCycleType = z.infer<typeof PerformanceCycleTypeSchema>;

export const PERFORMANCE_CYCLE_STATUSES = [
  "draft", "goal_setting_open", "self_assessment_open", "manager_assessment_open", "calibration", "acknowledgement", "closed", "cancelled",
] as const;
export const PerformanceCycleStatusSchema = z.enum(PERFORMANCE_CYCLE_STATUSES);
export type PerformanceCycleStatus = z.infer<typeof PerformanceCycleStatusSchema>;

export const PERFORMANCE_GOAL_STATUSES = ["active", "not_applicable"] as const;
export const PerformanceGoalStatusSchema = z.enum(PERFORMANCE_GOAL_STATUSES);
export type PerformanceGoalStatus = z.infer<typeof PerformanceGoalStatusSchema>;

export const PERFORMANCE_REVIEWER_ROLES = ["manager", "reviewer"] as const;
export const PerformanceReviewerRoleSchema = z.enum(PERFORMANCE_REVIEWER_ROLES);
export type PerformanceReviewerRole = z.infer<typeof PerformanceReviewerRoleSchema>;

export const PERFORMANCE_REVIEWER_ASSIGNMENT_STATUSES = ["active", "reassigned"] as const;
export const PerformanceReviewerAssignmentStatusSchema = z.enum(PERFORMANCE_REVIEWER_ASSIGNMENT_STATUSES);
export type PerformanceReviewerAssignmentStatus = z.infer<typeof PerformanceReviewerAssignmentStatusSchema>;

export const PERFORMANCE_ASSESSMENT_TYPES = ["self", "manager", "reviewer"] as const;
export const PerformanceAssessmentTypeSchema = z.enum(PERFORMANCE_ASSESSMENT_TYPES);
export type PerformanceAssessmentType = z.infer<typeof PerformanceAssessmentTypeSchema>;

export const PERFORMANCE_ASSESSMENT_STATUSES = ["not_started", "draft", "submitted"] as const;
export const PerformanceAssessmentStatusSchema = z.enum(PERFORMANCE_ASSESSMENT_STATUSES);
export type PerformanceAssessmentStatus = z.infer<typeof PerformanceAssessmentStatusSchema>;

export const PERFORMANCE_OUTCOME_STATUSES = ["draft", "published", "acknowledged", "appealed", "reopened", "closed"] as const;
export const PerformanceOutcomeStatusSchema = z.enum(PERFORMANCE_OUTCOME_STATUSES);
export type PerformanceOutcomeStatus = z.infer<typeof PerformanceOutcomeStatusSchema>;

export const PERFORMANCE_ACKNOWLEDGEMENT_AGREEMENTS = ["agree", "disagree"] as const;
export const PerformanceAcknowledgementAgreementSchema = z.enum(PERFORMANCE_ACKNOWLEDGEMENT_AGREEMENTS);
export type PerformanceAcknowledgementAgreement = z.infer<typeof PerformanceAcknowledgementAgreementSchema>;

export const PERFORMANCE_APPEAL_STATUSES = ["submitted", "under_review", "upheld", "overturned", "withdrawn"] as const;
export const PerformanceAppealStatusSchema = z.enum(PERFORMANCE_APPEAL_STATUSES);
export type PerformanceAppealStatus = z.infer<typeof PerformanceAppealStatusSchema>;

export const PERFORMANCE_APPEAL_DECISIONS = ["uphold", "overturn"] as const;
export const PerformanceAppealDecisionSchema = z.enum(PERFORMANCE_APPEAL_DECISIONS);
export type PerformanceAppealDecision = z.infer<typeof PerformanceAppealDecisionSchema>;

const decimal = z.union([z.string(), z.number()]).transform((v) => String(v));
const nullableDecimal = z.union([z.string(), z.number()]).nullable().transform((v) => (v === null ? null : String(v)));

// --- KPI library ---

export const PerformanceKpiDefinitionRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  unitOfMeasure: PerformanceUnitOfMeasureSchema,
});
export type PerformanceKpiDefinitionRow = z.infer<typeof PerformanceKpiDefinitionRowSchema>;

export function parsePerformanceKpiDefinitionRow(row: Record<string, unknown>): PerformanceKpiDefinitionRow {
  return PerformanceKpiDefinitionRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    description: row.description ?? null,
    unitOfMeasure: row.unit_of_measure,
  });
}

export const PerformanceKpiDefinitionVersionRowSchema = z.object({
  id: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: PerformanceKpiVersionStatusSchema,
  scoringMethod: PerformanceScoringMethodSchema,
  targetDirection: PerformanceTargetDirectionSchema.nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceKpiDefinitionVersionRow = z.infer<typeof PerformanceKpiDefinitionVersionRowSchema>;

export function parsePerformanceKpiDefinitionVersionRow(row: Record<string, unknown>): PerformanceKpiDefinitionVersionRow {
  return PerformanceKpiDefinitionVersionRowSchema.parse({
    id: row.id,
    versionNumber: row.version_number,
    status: row.status,
    scoringMethod: row.scoring_method,
    targetDirection: row.target_direction ?? null,
    recordVersion: row.record_version,
  });
}

// --- Template ---

export const PerformanceTemplateRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  status: PerformanceTemplateStatusSchema,
  weightTotalRequired: decimal,
  requiresReviewerStage: z.boolean(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceTemplateRow = z.infer<typeof PerformanceTemplateRowSchema>;

export function parsePerformanceTemplateRow(row: Record<string, unknown>): PerformanceTemplateRow {
  return PerformanceTemplateRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    status: row.status,
    weightTotalRequired: row.weight_total_required,
    requiresReviewerStage: row.requires_reviewer_stage,
    recordVersion: row.record_version,
  });
}

export const PerformanceTemplateKpiItemRowSchema = z.object({
  id: z.string().uuid(),
  kpiDefinitionId: z.string().uuid(),
  kpiCode: z.string(),
  kpiName: z.string(),
  defaultWeight: decimal,
  isRequired: z.boolean(),
  sortOrder: z.number().int(),
});
export type PerformanceTemplateKpiItemRow = z.infer<typeof PerformanceTemplateKpiItemRowSchema>;

export function parsePerformanceTemplateKpiItemRow(row: Record<string, unknown>): PerformanceTemplateKpiItemRow {
  return PerformanceTemplateKpiItemRowSchema.parse({
    id: row.id,
    kpiDefinitionId: row.kpi_definition_id,
    kpiCode: row.kpi_code,
    kpiName: row.kpi_name,
    defaultWeight: row.default_weight,
    isRequired: row.is_required,
    sortOrder: row.sort_order,
  });
}

// --- Cycle ---

export const PerformanceCycleRowSchema = z.object({
  id: z.string().uuid(),
  templateId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  cycleType: PerformanceCycleTypeSchema,
  periodStart: z.string(),
  periodEnd: z.string(),
  status: PerformanceCycleStatusSchema,
  weightTotalRequired: decimal,
  recordVersion: z.number().int().positive(),
});
export type PerformanceCycleRow = z.infer<typeof PerformanceCycleRowSchema>;

export function parsePerformanceCycleRow(row: Record<string, unknown>): PerformanceCycleRow {
  return PerformanceCycleRowSchema.parse({
    id: row.id,
    templateId: row.template_id,
    code: row.code,
    name: row.name,
    cycleType: row.cycle_type,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    status: row.status,
    weightTotalRequired: row.weight_total_required,
    recordVersion: row.record_version,
  });
}

// --- Goal assignment ---

export const PerformanceGoalAssignmentRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string().nullable(),
  employeeFullName: z.string().nullable(),
  kpiDefinitionId: z.string().uuid(),
  kpiCode: z.string(),
  kpiName: z.string(),
  kpiVersionId: z.string().uuid(),
  weight: decimal,
  targetValue: nullableDecimal,
  targetUnit: z.string().nullable(),
  status: PerformanceGoalStatusSchema,
  naReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceGoalAssignmentRow = z.infer<typeof PerformanceGoalAssignmentRowSchema>;

export function parsePerformanceGoalAssignmentRow(row: Record<string, unknown>): PerformanceGoalAssignmentRow {
  return PerformanceGoalAssignmentRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number ?? null,
    employeeFullName: row.employee_full_name ?? null,
    kpiDefinitionId: row.kpi_definition_id,
    kpiCode: row.kpi_code,
    kpiName: row.kpi_name,
    kpiVersionId: row.kpi_version_id,
    weight: row.weight,
    targetValue: row.target_value ?? null,
    targetUnit: row.target_unit ?? null,
    status: row.status,
    naReason: row.na_reason ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceMyGoalAssignmentRowSchema = z.object({
  id: z.string().uuid(),
  cycleId: z.string().uuid(),
  kpiDefinitionId: z.string().uuid(),
  kpiCode: z.string(),
  kpiName: z.string(),
  kpiVersionId: z.string().uuid(),
  weight: decimal,
  targetValue: nullableDecimal,
  targetUnit: z.string().nullable(),
  status: PerformanceGoalStatusSchema,
  naReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceMyGoalAssignmentRow = z.infer<typeof PerformanceMyGoalAssignmentRowSchema>;

export function parsePerformanceMyGoalAssignmentRow(row: Record<string, unknown>): PerformanceMyGoalAssignmentRow {
  return PerformanceMyGoalAssignmentRowSchema.parse({
    id: row.id,
    cycleId: row.cycle_id,
    kpiDefinitionId: row.kpi_definition_id,
    kpiCode: row.kpi_code,
    kpiName: row.kpi_name,
    kpiVersionId: row.kpi_version_id,
    weight: row.weight,
    targetValue: row.target_value ?? null,
    targetUnit: row.target_unit ?? null,
    status: row.status,
    naReason: row.na_reason ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceGoalProgressEntryRowSchema = z.object({
  id: z.string().uuid(),
  actualValue: nullableDecimal,
  note: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  recordedBy: z.string().nullable(),
  recordedAt: z.string(),
});
export type PerformanceGoalProgressEntryRow = z.infer<typeof PerformanceGoalProgressEntryRowSchema>;

export function parsePerformanceGoalProgressEntryRow(row: Record<string, unknown>): PerformanceGoalProgressEntryRow {
  return PerformanceGoalProgressEntryRowSchema.parse({
    id: row.id,
    actualValue: row.actual_value ?? null,
    note: row.note ?? null,
    evidenceFileId: row.evidence_file_id ?? null,
    recordedBy: row.recorded_by ?? null,
    recordedAt: row.recorded_at,
  });
}

// --- Reviewer assignment ---

export const PerformanceReviewerAssignmentRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeFullName: z.string().nullable(),
  role: PerformanceReviewerRoleSchema,
  assignedToEmployeeId: z.string().uuid(),
  assignedToFullName: z.string().nullable(),
  status: PerformanceReviewerAssignmentStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type PerformanceReviewerAssignmentRow = z.infer<typeof PerformanceReviewerAssignmentRowSchema>;

export function parsePerformanceReviewerAssignmentRow(row: Record<string, unknown>): PerformanceReviewerAssignmentRow {
  return PerformanceReviewerAssignmentRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeFullName: row.employee_full_name ?? null,
    role: row.role,
    assignedToEmployeeId: row.assigned_to_employee_id,
    assignedToFullName: row.assigned_to_full_name ?? null,
    status: row.status,
    recordVersion: row.record_version,
  });
}

// --- Assessment ---

export const PerformanceAssessmentRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeFullName: z.string().nullable(),
  assessmentType: PerformanceAssessmentTypeSchema,
  assignedToEmployeeId: z.string().uuid(),
  assignedToFullName: z.string().nullable(),
  status: PerformanceAssessmentStatusSchema,
  overallComment: z.string().nullable(),
  submittedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceAssessmentRow = z.infer<typeof PerformanceAssessmentRowSchema>;

export function parsePerformanceAssessmentRow(row: Record<string, unknown>): PerformanceAssessmentRow {
  return PerformanceAssessmentRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeFullName: row.employee_full_name ?? null,
    assessmentType: row.assessment_type,
    assignedToEmployeeId: row.assigned_to_employee_id,
    assignedToFullName: row.assigned_to_full_name ?? null,
    status: row.status,
    overallComment: row.overall_comment ?? null,
    submittedAt: row.submitted_at ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceMyAssessmentRowSchema = z.object({
  id: z.string().uuid(),
  cycleId: z.string().uuid(),
  cycleCode: z.string(),
  employeeId: z.string().uuid(),
  employeeFullName: z.string().nullable(),
  assessmentType: PerformanceAssessmentTypeSchema,
  status: PerformanceAssessmentStatusSchema,
  overallComment: z.string().nullable(),
  submittedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceMyAssessmentRow = z.infer<typeof PerformanceMyAssessmentRowSchema>;

export function parsePerformanceMyAssessmentRow(row: Record<string, unknown>): PerformanceMyAssessmentRow {
  return PerformanceMyAssessmentRowSchema.parse({
    id: row.id,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    employeeId: row.employee_id,
    employeeFullName: row.employee_full_name ?? null,
    assessmentType: row.assessment_type,
    status: row.status,
    overallComment: row.overall_comment ?? null,
    submittedAt: row.submitted_at ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceAssessmentKpiScoreRowSchema = z.object({
  id: z.string().uuid(),
  goalAssignmentId: z.string().uuid(),
  kpiCode: z.string(),
  kpiName: z.string(),
  actualValue: nullableDecimal,
  manualScore: nullableDecimal,
  rawScore: decimal,
  scoreRationale: z.string(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceAssessmentKpiScoreRow = z.infer<typeof PerformanceAssessmentKpiScoreRowSchema>;

export function parsePerformanceAssessmentKpiScoreRow(row: Record<string, unknown>): PerformanceAssessmentKpiScoreRow {
  return PerformanceAssessmentKpiScoreRowSchema.parse({
    id: row.id,
    goalAssignmentId: row.goal_assignment_id,
    kpiCode: row.kpi_code,
    kpiName: row.kpi_name,
    actualValue: row.actual_value ?? null,
    manualScore: row.manual_score ?? null,
    rawScore: row.raw_score,
    scoreRationale: row.score_rationale,
    recordVersion: row.record_version,
  });
}

// --- Outcome ---

const scoreBreakdownEntry = z.object({
  goalAssignmentId: z.string().uuid(),
  kpiDefinitionId: z.string().uuid(),
  weight: decimal,
  rawScore: decimal,
  weightedContribution: decimal,
});
export type PerformanceScoreBreakdownEntry = z.infer<typeof scoreBreakdownEntry>;

function parseScoreBreakdown(value: unknown): PerformanceScoreBreakdownEntry[] {
  const arr = Array.isArray(value) ? value : [];
  return arr.map((entry) => scoreBreakdownEntry.parse(entry));
}

export const PerformanceOutcomeRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeFullName: z.string().nullable(),
  baselineScore: nullableDecimal,
  calibratedScore: nullableDecimal,
  finalScore: nullableDecimal,
  status: PerformanceOutcomeStatusSchema,
  publishedAt: z.string().nullable(),
  acknowledgementAgreement: PerformanceAcknowledgementAgreementSchema.nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceOutcomeRow = z.infer<typeof PerformanceOutcomeRowSchema>;

export function parsePerformanceOutcomeRow(row: Record<string, unknown>): PerformanceOutcomeRow {
  return PerformanceOutcomeRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeFullName: row.employee_full_name ?? null,
    baselineScore: row.baseline_score ?? null,
    calibratedScore: row.calibrated_score ?? null,
    finalScore: row.final_score ?? null,
    status: row.status,
    publishedAt: row.published_at ?? null,
    acknowledgementAgreement: row.acknowledgement_agreement ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceOutcomeDetailRowSchema = z.object({
  id: z.string().uuid(),
  cycleId: z.string().uuid(),
  employeeId: z.string().uuid(),
  baselineScore: nullableDecimal,
  calibratedScore: nullableDecimal,
  finalScore: nullableDecimal,
  scoreBreakdown: z.array(scoreBreakdownEntry),
  status: PerformanceOutcomeStatusSchema,
  publishedAt: z.string().nullable(),
  acknowledgementAgreement: PerformanceAcknowledgementAgreementSchema.nullable(),
  acknowledgementComment: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceOutcomeDetailRow = z.infer<typeof PerformanceOutcomeDetailRowSchema>;

export function parsePerformanceOutcomeDetailRow(row: Record<string, unknown>): PerformanceOutcomeDetailRow {
  return PerformanceOutcomeDetailRowSchema.parse({
    id: row.id,
    cycleId: row.cycle_id,
    employeeId: row.employee_id,
    baselineScore: row.baseline_score ?? null,
    calibratedScore: row.calibrated_score ?? null,
    finalScore: row.final_score ?? null,
    scoreBreakdown: parseScoreBreakdown(row.score_breakdown),
    status: row.status,
    publishedAt: row.published_at ?? null,
    acknowledgementAgreement: row.acknowledgement_agreement ?? null,
    acknowledgementComment: row.acknowledgement_comment ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceMyOutcomeRowSchema = z.object({
  id: z.string().uuid(),
  cycleId: z.string().uuid(),
  cycleCode: z.string(),
  baselineScore: nullableDecimal,
  calibratedScore: nullableDecimal,
  finalScore: nullableDecimal,
  scoreBreakdown: z.array(scoreBreakdownEntry),
  status: PerformanceOutcomeStatusSchema,
  publishedAt: z.string().nullable(),
  acknowledgementAgreement: PerformanceAcknowledgementAgreementSchema.nullable(),
  acknowledgementComment: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceMyOutcomeRow = z.infer<typeof PerformanceMyOutcomeRowSchema>;

export function parsePerformanceMyOutcomeRow(row: Record<string, unknown>): PerformanceMyOutcomeRow {
  return PerformanceMyOutcomeRowSchema.parse({
    id: row.id,
    cycleId: row.cycle_id,
    cycleCode: row.cycle_code,
    baselineScore: row.baseline_score ?? null,
    calibratedScore: row.calibrated_score ?? null,
    finalScore: row.final_score ?? null,
    scoreBreakdown: parseScoreBreakdown(row.score_breakdown),
    status: row.status,
    publishedAt: row.published_at ?? null,
    acknowledgementAgreement: row.acknowledgement_agreement ?? null,
    acknowledgementComment: row.acknowledgement_comment ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceCalibrationAdjustmentRowSchema = z.object({
  id: z.string().uuid(),
  previousScore: decimal,
  adjustedScore: decimal,
  adjustmentReason: z.string(),
  calibratedBy: z.string().nullable(),
  calibratedAt: z.string(),
});
export type PerformanceCalibrationAdjustmentRow = z.infer<typeof PerformanceCalibrationAdjustmentRowSchema>;

export function parsePerformanceCalibrationAdjustmentRow(row: Record<string, unknown>): PerformanceCalibrationAdjustmentRow {
  return PerformanceCalibrationAdjustmentRowSchema.parse({
    id: row.id,
    previousScore: row.previous_score,
    adjustedScore: row.adjusted_score,
    adjustmentReason: row.adjustment_reason,
    calibratedBy: row.calibrated_by ?? null,
    calibratedAt: row.calibrated_at,
  });
}

// --- Appeal ---

export const PerformanceAppealRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeFullName: z.string().nullable(),
  outcomeId: z.string().uuid(),
  appealReason: z.string(),
  status: PerformanceAppealStatusSchema,
  decisionReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceAppealRow = z.infer<typeof PerformanceAppealRowSchema>;

export function parsePerformanceAppealRow(row: Record<string, unknown>): PerformanceAppealRow {
  return PerformanceAppealRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeFullName: row.employee_full_name ?? null,
    outcomeId: row.outcome_id,
    appealReason: row.appeal_reason,
    status: row.status,
    decisionReason: row.decision_reason ?? null,
    recordVersion: row.record_version,
  });
}

export const PerformanceMyAppealRowSchema = z.object({
  id: z.string().uuid(),
  cycleId: z.string().uuid(),
  outcomeId: z.string().uuid(),
  appealReason: z.string(),
  status: PerformanceAppealStatusSchema,
  decisionReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PerformanceMyAppealRow = z.infer<typeof PerformanceMyAppealRowSchema>;

export function parsePerformanceMyAppealRow(row: Record<string, unknown>): PerformanceMyAppealRow {
  return PerformanceMyAppealRowSchema.parse({
    id: row.id,
    cycleId: row.cycle_id,
    outcomeId: row.outcome_id,
    appealReason: row.appeal_reason,
    status: row.status,
    decisionReason: row.decision_reason ?? null,
    recordVersion: row.record_version,
  });
}

// --- Reporting (k-anonymity) ---

export const PerformanceCycleScoreDistributionRowSchema = z.object({
  departmentOrgUnitId: z.string().uuid().nullable(),
  departmentName: z.string().nullable(),
  employeeCount: z.number().int().nonnegative(),
  avgFinalScore: nullableDecimal,
  suppressed: z.boolean(),
});
export type PerformanceCycleScoreDistributionRow = z.infer<typeof PerformanceCycleScoreDistributionRowSchema>;

export function parsePerformanceCycleScoreDistributionRow(row: Record<string, unknown>): PerformanceCycleScoreDistributionRow {
  return PerformanceCycleScoreDistributionRowSchema.parse({
    departmentOrgUnitId: row.department_org_unit_id ?? null,
    departmentName: row.department_name ?? null,
    employeeCount: row.employee_count,
    avgFinalScore: row.avg_final_score ?? null,
    suppressed: row.suppressed,
  });
}
