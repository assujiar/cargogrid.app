/**
 * Vendor Performance contract (PRC-264, CG-S11-PRC-015). Mirrors
 * supabase/migrations/20260730740000_create_procurement_vendor_performance.sql -- Zod
 * schemas + parse functions for the KPI catalogue, measurement runs, metric values,
 * scorecards/lines, source disputes, issues/corrective actions, manual adjustments, and
 * governed lifecycle recommendations, plus one *InputSchema per mutation, the same
 * shape server/contracts/vendor-contract/vendor-contract.ts already establishes.
 */

import { z } from "zod";

export const VENDOR_KPI_CODES = [
  "on_time_pickup",
  "on_time_delivery",
  "acceptance_rate",
  "response_time",
  "capacity_fulfillment",
  "compliance",
  "claims_damage",
  "rate_competitiveness",
  "rate_validity",
  "invoice_accuracy",
  "service_complaint_sla",
] as const;
export const VendorKpiCodeSchema = z.enum(VENDOR_KPI_CODES);
export type VendorKpiCode = z.infer<typeof VendorKpiCodeSchema>;

export const VENDOR_KPI_DEFINITION_STATUSES = ["draft", "published", "archived"] as const;
export const VendorKpiDefinitionStatusSchema = z.enum(VENDOR_KPI_DEFINITION_STATUSES);
export type VendorKpiDefinitionStatus = z.infer<typeof VendorKpiDefinitionStatusSchema>;

export const VENDOR_KPI_TARGET_OPERATORS = ["gte", "lte"] as const;
export const VendorKpiTargetOperatorSchema = z.enum(VENDOR_KPI_TARGET_OPERATORS);

export const VENDOR_KPI_UNITS = ["percent", "hours", "score", "count"] as const;
export const VendorKpiUnitSchema = z.enum(VENDOR_KPI_UNITS);

export const VENDOR_KPI_BANDS = ["excellent", "good", "watch", "poor"] as const;
export const VendorKpiBandSchema = z.enum(VENDOR_KPI_BANDS);
export type VendorKpiBand = z.infer<typeof VendorKpiBandSchema>;

export const BandThresholdsSchema = z.object({ excellent: z.number(), good: z.number(), watch: z.number() });
export type BandThresholds = z.infer<typeof BandThresholdsSchema>;

export const VendorKpiDefinitionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  versionNo: z.number().int().positive(),
  status: VendorKpiDefinitionStatusSchema,
  name: z.string(),
  description: z.string().nullable(),
  measurementWindowDays: z.number().int().positive(),
  minSampleSize: z.number().int().nonnegative(),
  targetValue: z.number(),
  targetOperator: VendorKpiTargetOperatorSchema,
  weight: z.number(),
  unit: VendorKpiUnitSchema,
  bandThresholds: BandThresholdsSchema,
  exclusionRules: z.record(z.string(), z.unknown()),
  isComputable: z.boolean(),
  sourceNote: z.string().nullable(),
  roundingScale: z.number().int(),
  supersedesDefinitionId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorKpiDefinition = z.infer<typeof VendorKpiDefinitionSchema>;

export function parseVendorKpiDefinition(row: Record<string, unknown>): VendorKpiDefinition {
  return VendorKpiDefinitionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    kpiCode: row.kpi_code,
    versionNo: row.version_no,
    status: row.status,
    name: row.name,
    description: row.description,
    measurementWindowDays: row.measurement_window_days,
    minSampleSize: row.min_sample_size,
    targetValue: Number(row.target_value),
    targetOperator: row.target_operator,
    weight: Number(row.weight),
    unit: row.unit,
    bandThresholds: row.band_thresholds,
    exclusionRules: row.exclusion_rules ?? {},
    isComputable: row.is_computable,
    sourceNote: row.source_note,
    roundingScale: row.rounding_scale,
    supersedesDefinitionId: row.supersedes_definition_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorKpiMetricValueSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  kpiDefinitionId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  windowStart: z.string(),
  windowEnd: z.string(),
  versionNo: z.number().int().positive(),
  isCurrent: z.boolean(),
  runId: z.string().uuid(),
  rawNumerator: z.number().nullable(),
  rawDenominator: z.number().nullable(),
  sampleSize: z.number().int().nonnegative(),
  computedValue: z.number().nullable(),
  normalizedScore: z.number().nullable(),
  isComputable: z.boolean(),
  computationNote: z.string().nullable(),
  excludedCount: z.number().int().nonnegative(),
  sourceEvidence: z.record(z.string(), z.unknown()),
  supersedesMetricValueId: z.string().uuid().nullable(),
  calculatedAt: z.string(),
});
export type VendorKpiMetricValue = z.infer<typeof VendorKpiMetricValueSchema>;

export function parseVendorKpiMetricValue(row: Record<string, unknown>): VendorKpiMetricValue {
  return VendorKpiMetricValueSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    kpiDefinitionId: row.kpi_definition_id,
    kpiCode: row.kpi_code,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    versionNo: row.version_no,
    isCurrent: row.is_current,
    runId: row.run_id,
    rawNumerator: row.raw_numerator == null ? null : Number(row.raw_numerator),
    rawDenominator: row.raw_denominator == null ? null : Number(row.raw_denominator),
    sampleSize: row.sample_size,
    computedValue: row.computed_value == null ? null : Number(row.computed_value),
    normalizedScore: row.normalized_score == null ? null : Number(row.normalized_score),
    isComputable: row.is_computable,
    computationNote: row.computation_note,
    excludedCount: row.excluded_count,
    sourceEvidence: row.source_evidence ?? {},
    supersedesMetricValueId: row.supersedes_metric_value_id,
    calculatedAt: row.calculated_at,
  });
}

export const VENDOR_KPI_SCORECARD_STATUSES = ["published", "superseded"] as const;
export const VendorKpiScorecardStatusSchema = z.enum(VENDOR_KPI_SCORECARD_STATUSES);

export const VendorKpiScorecardSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  windowStart: z.string(),
  windowEnd: z.string(),
  versionNo: z.number().int().positive(),
  isCurrent: z.boolean(),
  status: VendorKpiScorecardStatusSchema,
  compositeScore: z.number().nullable(),
  band: VendorKpiBandSchema.nullable(),
  computableWeightTotal: z.number(),
  totalWeightDefined: z.number(),
  coverageNote: z.string().nullable(),
  runId: z.string().uuid().nullable(),
  supersedesScorecardId: z.string().uuid().nullable(),
  publishedByAuthUserId: z.string().uuid().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorKpiScorecard = z.infer<typeof VendorKpiScorecardSchema>;

export function parseVendorKpiScorecard(row: Record<string, unknown>): VendorKpiScorecard {
  return VendorKpiScorecardSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    versionNo: row.version_no,
    isCurrent: row.is_current,
    status: row.status,
    compositeScore: row.composite_score == null ? null : Number(row.composite_score),
    band: row.band,
    computableWeightTotal: Number(row.computable_weight_total),
    totalWeightDefined: Number(row.total_weight_defined),
    coverageNote: row.coverage_note,
    runId: row.run_id,
    supersedesScorecardId: row.supersedes_scorecard_id,
    publishedByAuthUserId: row.published_by_auth_user_id,
    publishedBy: row.published_by,
    publishedAt: row.published_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorKpiScorecardDrilldownLineSchema = z.object({
  lineId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  kpiNameSnapshot: z.string(),
  weightSnapshot: z.number(),
  targetValueSnapshot: z.number(),
  targetOperatorSnapshot: VendorKpiTargetOperatorSchema,
  bandThresholdsSnapshot: BandThresholdsSchema,
  computedValue: z.number().nullable(),
  normalizedScore: z.number().nullable(),
  band: VendorKpiBandSchema.nullable(),
  isComputable: z.boolean(),
  adjusted: z.boolean(),
  rawNumerator: z.number().nullable(),
  rawDenominator: z.number().nullable(),
  sampleSize: z.number().int().nullable(),
  excludedCount: z.number().int().nullable(),
  computationNote: z.string().nullable(),
  sourceEvidence: z.record(z.string(), z.unknown()).nullable(),
  calculatedAt: z.string().nullable(),
});
export type VendorKpiScorecardDrilldownLine = z.infer<typeof VendorKpiScorecardDrilldownLineSchema>;

export function parseVendorKpiScorecardDrilldownLine(row: Record<string, unknown>): VendorKpiScorecardDrilldownLine {
  return VendorKpiScorecardDrilldownLineSchema.parse({
    lineId: row.line_id,
    kpiCode: row.kpi_code,
    kpiNameSnapshot: row.kpi_name_snapshot,
    weightSnapshot: Number(row.weight_snapshot),
    targetValueSnapshot: Number(row.target_value_snapshot),
    targetOperatorSnapshot: row.target_operator_snapshot,
    bandThresholdsSnapshot: row.band_thresholds_snapshot,
    computedValue: row.computed_value == null ? null : Number(row.computed_value),
    normalizedScore: row.normalized_score == null ? null : Number(row.normalized_score),
    band: row.band,
    isComputable: row.is_computable,
    adjusted: row.adjusted,
    rawNumerator: row.raw_numerator == null ? null : Number(row.raw_numerator),
    rawDenominator: row.raw_denominator == null ? null : Number(row.raw_denominator),
    sampleSize: row.sample_size == null ? null : Number(row.sample_size),
    excludedCount: row.excluded_count == null ? null : Number(row.excluded_count),
    computationNote: row.computation_note,
    sourceEvidence: row.source_evidence ?? {},
    calculatedAt: row.calculated_at,
  });
}

/** True whenever contributing_source_ids has been stripped from source_evidence (no PRC:View cost). */
export function isVendorKpiEvidenceMasked(line: Pick<VendorKpiScorecardDrilldownLine, "sourceEvidence">): boolean {
  return line.sourceEvidence != null && !("contributing_source_ids" in line.sourceEvidence);
}

export const VENDOR_KPI_DISPUTE_STATUSES = ["pending", "upheld", "rejected"] as const;
export const VendorKpiDisputeStatusSchema = z.enum(VENDOR_KPI_DISPUTE_STATUSES);

export const VendorKpiSourceDisputeSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  sourceId: z.string().uuid(),
  sourceLabel: z.string().nullable(),
  reason: z.string(),
  status: VendorKpiDisputeStatusSchema,
  raisedByAuthUserId: z.string().uuid().nullable(),
  raisedBy: z.string().nullable(),
  raisedAt: z.string(),
  decidedByAuthUserId: z.string().uuid().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decisionNotes: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorKpiSourceDispute = z.infer<typeof VendorKpiSourceDisputeSchema>;

export function parseVendorKpiSourceDispute(row: Record<string, unknown>): VendorKpiSourceDispute {
  return VendorKpiSourceDisputeSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    kpiCode: row.kpi_code,
    sourceId: row.source_id,
    sourceLabel: row.source_label,
    reason: row.reason,
    status: row.status,
    raisedByAuthUserId: row.raised_by_auth_user_id,
    raisedBy: row.raised_by,
    raisedAt: row.raised_at,
    decidedByAuthUserId: row.decided_by_auth_user_id,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    decisionNotes: row.decision_notes,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VENDOR_PERFORMANCE_ISSUE_SEVERITIES = ["low", "medium", "high", "critical"] as const;
export const VendorPerformanceIssueSeveritySchema = z.enum(VENDOR_PERFORMANCE_ISSUE_SEVERITIES);
export const VENDOR_PERFORMANCE_ISSUE_STATUSES = ["open", "in_progress", "resolved", "closed"] as const;
export const VendorPerformanceIssueStatusSchema = z.enum(VENDOR_PERFORMANCE_ISSUE_STATUSES);

export const VendorPerformanceIssueSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  scorecardId: z.string().uuid().nullable(),
  kpiCode: VendorKpiCodeSchema.nullable(),
  severity: VendorPerformanceIssueSeveritySchema,
  title: z.string(),
  description: z.string().nullable(),
  status: VendorPerformanceIssueStatusSchema,
  raisedByAuthUserId: z.string().uuid().nullable(),
  raisedBy: z.string().nullable(),
  raisedAt: z.string(),
  resolvedByAuthUserId: z.string().uuid().nullable(),
  resolvedBy: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  resolutionNote: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorPerformanceIssue = z.infer<typeof VendorPerformanceIssueSchema>;

export function parseVendorPerformanceIssue(row: Record<string, unknown>): VendorPerformanceIssue {
  return VendorPerformanceIssueSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    scorecardId: row.scorecard_id,
    kpiCode: row.kpi_code,
    severity: row.severity,
    title: row.title,
    description: row.description,
    status: row.status,
    raisedByAuthUserId: row.raised_by_auth_user_id,
    raisedBy: row.raised_by,
    raisedAt: row.raised_at,
    resolvedByAuthUserId: row.resolved_by_auth_user_id,
    resolvedBy: row.resolved_by,
    resolvedAt: row.resolved_at,
    resolutionNote: row.resolution_note,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VENDOR_PERFORMANCE_CORRECTIVE_ACTION_STATUSES = ["open", "in_progress", "completed", "cancelled"] as const;
export const VendorPerformanceCorrectiveActionStatusSchema = z.enum(VENDOR_PERFORMANCE_CORRECTIVE_ACTION_STATUSES);

export const VendorPerformanceCorrectiveActionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  issueId: z.string().uuid(),
  description: z.string(),
  ownerLabel: z.string().nullable(),
  dueDate: z.string().nullable(),
  status: VendorPerformanceCorrectiveActionStatusSchema,
  completedAt: z.string().nullable(),
  completionNote: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorPerformanceCorrectiveAction = z.infer<typeof VendorPerformanceCorrectiveActionSchema>;

export function parseVendorPerformanceCorrectiveAction(row: Record<string, unknown>): VendorPerformanceCorrectiveAction {
  return VendorPerformanceCorrectiveActionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    issueId: row.issue_id,
    description: row.description,
    ownerLabel: row.owner_label,
    dueDate: row.due_date,
    status: row.status,
    completedAt: row.completed_at,
    completionNote: row.completion_note,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** True when overdue (computed client-side, mirrors the RPC layer's own read-time convention -- never a stored status). */
export function isVendorPerformanceCorrectiveActionOverdue(action: Pick<VendorPerformanceCorrectiveAction, "status" | "dueDate">): boolean {
  if (action.status === "completed" || action.status === "cancelled" || !action.dueDate) return false;
  return new Date(action.dueDate).getTime() < Date.now();
}

export const VENDOR_KPI_MANUAL_ADJUSTMENT_STATUSES = ["pending_approval", "approved", "rejected"] as const;
export const VendorKpiManualAdjustmentStatusSchema = z.enum(VENDOR_KPI_MANUAL_ADJUSTMENT_STATUSES);

export const VendorKpiManualAdjustmentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scorecardId: z.string().uuid(),
  scorecardLineId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  originalNormalizedScore: z.number().nullable(),
  adjustedNormalizedScore: z.number(),
  reason: z.string(),
  requestedByAuthUserId: z.string().uuid(),
  requestedBy: z.string().nullable(),
  requestedAt: z.string(),
  status: VendorKpiManualAdjustmentStatusSchema,
  decidedByAuthUserId: z.string().uuid().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decisionNotes: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorKpiManualAdjustment = z.infer<typeof VendorKpiManualAdjustmentSchema>;

export function parseVendorKpiManualAdjustment(row: Record<string, unknown>): VendorKpiManualAdjustment {
  return VendorKpiManualAdjustmentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scorecardId: row.scorecard_id,
    scorecardLineId: row.scorecard_line_id,
    kpiCode: row.kpi_code,
    originalNormalizedScore: row.original_normalized_score == null ? null : Number(row.original_normalized_score),
    adjustedNormalizedScore: Number(row.adjusted_normalized_score),
    reason: row.reason,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    requestedBy: row.requested_by,
    requestedAt: row.requested_at,
    status: row.status,
    decidedByAuthUserId: row.decided_by_auth_user_id,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    decisionNotes: row.decision_notes,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS = ["none", "watch", "suspend", "blacklist", "reactivate"] as const;
export const VendorLifecycleRecommendationActionSchema = z.enum(VENDOR_LIFECYCLE_RECOMMENDATION_ACTIONS);
export const VENDOR_LIFECYCLE_RECOMMENDATION_STATUSES = ["pending", "decided"] as const;
export const VendorLifecycleRecommendationStatusSchema = z.enum(VENDOR_LIFECYCLE_RECOMMENDATION_STATUSES);

export const VendorLifecycleRecommendationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  scorecardId: z.string().uuid().nullable(),
  recommendedAction: VendorLifecycleRecommendationActionSchema,
  recommendedRationale: z.string(),
  recommendedByAuthUserId: z.string().uuid().nullable(),
  recommendedBy: z.string().nullable(),
  recommendedAt: z.string(),
  status: VendorLifecycleRecommendationStatusSchema,
  decidedAction: VendorLifecycleRecommendationActionSchema.nullable(),
  decidedByAuthUserId: z.string().uuid().nullable(),
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decisionNotes: z.string().nullable(),
  evidenceRef: z.string().nullable(),
  executed: z.boolean(),
  executedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorLifecycleRecommendation = z.infer<typeof VendorLifecycleRecommendationSchema>;

export function parseVendorLifecycleRecommendation(row: Record<string, unknown>): VendorLifecycleRecommendation {
  return VendorLifecycleRecommendationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    scorecardId: row.scorecard_id,
    recommendedAction: row.recommended_action,
    recommendedRationale: row.recommended_rationale,
    recommendedByAuthUserId: row.recommended_by_auth_user_id,
    recommendedBy: row.recommended_by,
    recommendedAt: row.recommended_at,
    status: row.status,
    decidedAction: row.decided_action,
    decidedByAuthUserId: row.decided_by_auth_user_id,
    decidedBy: row.decided_by,
    decidedAt: row.decided_at,
    decisionNotes: row.decision_notes,
    evidenceRef: row.evidence_ref,
    executed: row.executed,
    executedAt: row.executed_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorKpiMeasurementRunSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  windowStart: z.string(),
  windowEnd: z.string(),
  triggeredBy: z.enum(["scheduled", "manual", "recalculation"]),
  status: z.enum(["completed", "partial", "failed"]),
  kpiCount: z.number().int().nonnegative(),
  computableCount: z.number().int().nonnegative(),
  sourceCheckpoint: z.record(z.string(), z.unknown()),
  createdAt: z.string(),
});
export type VendorKpiMeasurementRun = z.infer<typeof VendorKpiMeasurementRunSchema>;

export function parseVendorKpiMeasurementRun(row: Record<string, unknown>): VendorKpiMeasurementRun {
  return VendorKpiMeasurementRunSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    triggeredBy: row.triggered_by,
    status: row.status,
    kpiCount: row.kpi_count,
    computableCount: row.computable_count,
    sourceCheckpoint: row.source_checkpoint ?? {},
    createdAt: row.created_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const CreateVendorKpiDefinitionDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  measurementWindowDays: z.number().int().positive(),
  minSampleSize: z.number().int().nonnegative().default(1),
  targetValue: z.number(),
  targetOperator: VendorKpiTargetOperatorSchema,
  weight: z.number().positive().max(100),
  unit: VendorKpiUnitSchema,
  bandThresholds: BandThresholdsSchema.nullable().default(null),
  exclusionRules: z.record(z.string(), z.unknown()).nullable().default(null),
  roundingScale: z.number().int().min(0).max(6).default(2),
  isComputable: z.boolean().default(true),
  sourceNote: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateVendorKpiDefinitionDraftInput = z.input<typeof CreateVendorKpiDefinitionDraftInputSchema>;

export const PublishVendorKpiDefinitionInputSchema = z.object({
  definitionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishVendorKpiDefinitionInput = z.input<typeof PublishVendorKpiDefinitionInputSchema>;

export const ArchiveVendorKpiDefinitionInputSchema = z.object({
  definitionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ArchiveVendorKpiDefinitionInput = z.input<typeof ArchiveVendorKpiDefinitionInputSchema>;

export const CalculateVendorKpiMetricsInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  windowStart: z.string().min(1),
  windowEnd: z.string().min(1),
  triggeredBy: z.enum(["scheduled", "manual", "recalculation"]).default("manual"),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CalculateVendorKpiMetricsInput = z.input<typeof CalculateVendorKpiMetricsInputSchema>;

export const PublishVendorKpiScorecardInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  windowStart: z.string().min(1),
  windowEnd: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishVendorKpiScorecardInput = z.input<typeof PublishVendorKpiScorecardInputSchema>;

export const RaiseVendorKpiSourceDisputeInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  sourceId: z.string().uuid(),
  sourceLabel: z.string().nullable().default(null),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RaiseVendorKpiSourceDisputeInput = z.input<typeof RaiseVendorKpiSourceDisputeInputSchema>;

export const DecideVendorKpiSourceDisputeInputSchema = z.object({
  disputeId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["upheld", "rejected"]),
  decisionNotes: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideVendorKpiSourceDisputeInput = z.input<typeof DecideVendorKpiSourceDisputeInputSchema>;

export const RaiseVendorPerformanceIssueInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  scorecardId: z.string().uuid().nullable().default(null),
  kpiCode: VendorKpiCodeSchema.nullable().default(null),
  severity: VendorPerformanceIssueSeveritySchema,
  title: z.string().min(1),
  description: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RaiseVendorPerformanceIssueInput = z.input<typeof RaiseVendorPerformanceIssueInputSchema>;

export const UpdateVendorPerformanceIssueStatusInputSchema = z.object({
  issueId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  status: VendorPerformanceIssueStatusSchema,
  resolutionNote: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateVendorPerformanceIssueStatusInput = z.input<typeof UpdateVendorPerformanceIssueStatusInputSchema>;

export const AddVendorPerformanceCorrectiveActionInputSchema = z.object({
  issueId: z.string().uuid(),
  description: z.string().min(1),
  ownerLabel: z.string().nullable().default(null),
  dueDate: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddVendorPerformanceCorrectiveActionInput = z.input<typeof AddVendorPerformanceCorrectiveActionInputSchema>;

export const UpdateVendorPerformanceCorrectiveActionStatusInputSchema = z.object({
  actionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  status: VendorPerformanceCorrectiveActionStatusSchema,
  completionNote: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateVendorPerformanceCorrectiveActionStatusInput = z.input<typeof UpdateVendorPerformanceCorrectiveActionStatusInputSchema>;

export const RequestVendorKpiManualAdjustmentInputSchema = z.object({
  scorecardId: z.string().uuid(),
  kpiCode: VendorKpiCodeSchema,
  adjustedNormalizedScore: z.number().min(0).max(100),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestVendorKpiManualAdjustmentInput = z.input<typeof RequestVendorKpiManualAdjustmentInputSchema>;

export const DecideVendorKpiManualAdjustmentInputSchema = z.object({
  adjustmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["approved", "rejected"]),
  decisionNotes: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideVendorKpiManualAdjustmentInput = z.input<typeof DecideVendorKpiManualAdjustmentInputSchema>;

export const EvaluateVendorLifecycleRecommendationInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  scorecardId: z.string().uuid().nullable().default(null),
  overrideAction: VendorLifecycleRecommendationActionSchema.nullable().default(null),
  rationale: z.string().nullable().default(null),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EvaluateVendorLifecycleRecommendationInput = z.input<typeof EvaluateVendorLifecycleRecommendationInputSchema>;

export const DecideVendorLifecycleRecommendationInputSchema = z.object({
  recommendationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decidedAction: VendorLifecycleRecommendationActionSchema,
  decisionNotes: z.string().min(1),
  evidenceRef: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideVendorLifecycleRecommendationInput = z.input<typeof DecideVendorLifecycleRecommendationInputSchema>;
