/**
 * Vendor Performance mutation primitives (PRC-264, CG-S11-PRC-015). Thin, typed
 * wrappers around the write RPCs supabase/migrations/20260730740000_create_
 * procurement_vendor_performance.sql adds -- the same KNOWN_MUTATION_ERROR_CODES /
 * classifyError / callRpc shape server/mutations/vendor-contract.ts already
 * establishes.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorKpiDefinitionDraftInputSchema,
  PublishVendorKpiDefinitionInputSchema,
  ArchiveVendorKpiDefinitionInputSchema,
  CalculateVendorKpiMetricsInputSchema,
  PublishVendorKpiScorecardInputSchema,
  RaiseVendorKpiSourceDisputeInputSchema,
  DecideVendorKpiSourceDisputeInputSchema,
  RaiseVendorPerformanceIssueInputSchema,
  UpdateVendorPerformanceIssueStatusInputSchema,
  AddVendorPerformanceCorrectiveActionInputSchema,
  UpdateVendorPerformanceCorrectiveActionStatusInputSchema,
  RequestVendorKpiManualAdjustmentInputSchema,
  DecideVendorKpiManualAdjustmentInputSchema,
  EvaluateVendorLifecycleRecommendationInputSchema,
  DecideVendorLifecycleRecommendationInputSchema,
  parseVendorKpiDefinition,
  parseVendorKpiMetricValue,
  parseVendorKpiScorecard,
  parseVendorKpiSourceDispute,
  parseVendorPerformanceIssue,
  parseVendorPerformanceCorrectiveAction,
  parseVendorKpiManualAdjustment,
  parseVendorLifecycleRecommendation,
  type CreateVendorKpiDefinitionDraftInput,
  type PublishVendorKpiDefinitionInput,
  type ArchiveVendorKpiDefinitionInput,
  type CalculateVendorKpiMetricsInput,
  type PublishVendorKpiScorecardInput,
  type RaiseVendorKpiSourceDisputeInput,
  type DecideVendorKpiSourceDisputeInput,
  type RaiseVendorPerformanceIssueInput,
  type UpdateVendorPerformanceIssueStatusInput,
  type AddVendorPerformanceCorrectiveActionInput,
  type UpdateVendorPerformanceCorrectiveActionStatusInput,
  type RequestVendorKpiManualAdjustmentInput,
  type DecideVendorKpiManualAdjustmentInput,
  type EvaluateVendorLifecycleRecommendationInput,
  type DecideVendorLifecycleRecommendationInput,
  type VendorKpiDefinition,
  type VendorKpiMetricValue,
  type VendorKpiScorecard,
  type VendorKpiSourceDispute,
  type VendorPerformanceIssue,
  type VendorPerformanceCorrectiveAction,
  type VendorKpiManualAdjustment,
  type VendorLifecycleRecommendation,
} from "../contracts/vendor-performance/vendor-performance.ts";

export type VendorPerformanceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_PERFORMANCE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "vendor_profile_not_found",
  "vendor_kpi_definition_not_found",
  "vendor_kpi_dispute_not_found",
  "vendor_kpi_scorecard_not_found",
  "vendor_kpi_scorecard_line_not_found",
  "vendor_kpi_manual_adjustment_not_found",
  "vendor_performance_issue_not_found",
  "vendor_performance_corrective_action_not_found",
  "vendor_lifecycle_recommendation_not_found",
  "vendor_kpi_measurement_run_not_found",
  "metrics_not_calculated",
  "insufficient_kpi_coverage",
  "insufficient_sample",
  "invalid_window",
  "invalid_kpi_code",
  "invalid_target_operator",
  "invalid_decision",
  "invalid_action",
  "invalid_status",
  "invalid_triggered_by",
  "invalid_transition",
  "invalid_score",
  "reason_required",
  "title_required",
  "description_required",
  "completion_note_required",
  "basis_required",
  "evidence_required",
  "self_approval_not_allowed",
  "adjustment_already_pending",
  "dispute_already_pending",
  "stale_version",
  "idempotency_key_conflict",
] as const;
type KnownVendorPerformanceMutationErrorCode = (typeof VENDOR_PERFORMANCE_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorPerformanceMutationErrorCode = KnownVendorPerformanceMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorPerformanceMutationError extends Error {
  readonly code: VendorPerformanceMutationErrorCode;

  constructor(code: VendorPerformanceMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorPerformanceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorPerformanceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_PERFORMANCE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorPerformanceMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: VendorPerformanceMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorPerformanceMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireRow<T>(data: unknown, parse: (row: Record<string, unknown>) => T, fn: string): T {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorPerformanceMutationError("invalid_response", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

// -- KPI catalogue -----------------------------------------------------------

export async function createVendorKpiDefinitionDraft(client: VendorPerformanceMutationRpcClient, input: CreateVendorKpiDefinitionDraftInput): Promise<VendorKpiDefinition> {
  const p = CreateVendorKpiDefinitionDraftInputSchema.parse(input);
  const data = await callRpc(client, "create_vendor_kpi_definition_draft", {
    p_tenant_id: p.tenantId,
    p_kpi_code: p.kpiCode,
    p_name: p.name,
    p_description: p.description,
    p_measurement_window_days: p.measurementWindowDays,
    p_min_sample_size: p.minSampleSize,
    p_target_value: p.targetValue,
    p_target_operator: p.targetOperator,
    p_weight: p.weight,
    p_unit: p.unit,
    p_band_thresholds: p.bandThresholds,
    p_exclusion_rules: p.exclusionRules,
    p_rounding_scale: p.roundingScale,
    p_is_computable: p.isComputable,
    p_source_note: p.sourceNote,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorKpiDefinition, "create_vendor_kpi_definition_draft");
}

export async function publishVendorKpiDefinition(client: VendorPerformanceMutationRpcClient, input: PublishVendorKpiDefinitionInput): Promise<VendorKpiDefinition> {
  const p = PublishVendorKpiDefinitionInputSchema.parse(input);
  const data = await callRpc(client, "publish_vendor_kpi_definition", { p_definition_id: p.definitionId, p_expected_version: p.expectedVersion, p_actor_auth_user_id: p.actorAuthUserId, p_actor_label: p.actorLabel });
  return requireRow(data, parseVendorKpiDefinition, "publish_vendor_kpi_definition");
}

export async function archiveVendorKpiDefinition(client: VendorPerformanceMutationRpcClient, input: ArchiveVendorKpiDefinitionInput): Promise<VendorKpiDefinition> {
  const p = ArchiveVendorKpiDefinitionInputSchema.parse(input);
  const data = await callRpc(client, "archive_vendor_kpi_definition", { p_definition_id: p.definitionId, p_expected_version: p.expectedVersion, p_reason: p.reason, p_actor_auth_user_id: p.actorAuthUserId, p_actor_label: p.actorLabel });
  return requireRow(data, parseVendorKpiDefinition, "archive_vendor_kpi_definition");
}

// -- Measurement / scorecards -------------------------------------------------

/** Calculates (or recalculates) every published KPI category for one vendor/window; returns the resulting current metric value rows. */
export async function calculateVendorKpiMetrics(client: VendorPerformanceMutationRpcClient, input: CalculateVendorKpiMetricsInput): Promise<VendorKpiMetricValue[]> {
  const p = CalculateVendorKpiMetricsInputSchema.parse(input);
  const data = await callRpc(client, "calculate_vendor_kpi_metrics", {
    p_tenant_id: p.tenantId,
    p_vendor_master_id: p.vendorMasterId,
    p_window_start: p.windowStart,
    p_window_end: p.windowEnd,
    p_triggered_by: p.triggeredBy,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return (Array.isArray(data) ? data : []).map((row: Record<string, unknown>) => parseVendorKpiMetricValue(row));
}

export async function publishVendorKpiScorecard(client: VendorPerformanceMutationRpcClient, input: PublishVendorKpiScorecardInput): Promise<VendorKpiScorecard> {
  const p = PublishVendorKpiScorecardInputSchema.parse(input);
  const data = await callRpc(client, "publish_vendor_kpi_scorecard", {
    p_tenant_id: p.tenantId,
    p_vendor_master_id: p.vendorMasterId,
    p_window_start: p.windowStart,
    p_window_end: p.windowEnd,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorKpiScorecard, "publish_vendor_kpi_scorecard");
}

// -- Source disputes -----------------------------------------------------------

export async function raiseVendorKpiSourceDispute(client: VendorPerformanceMutationRpcClient, input: RaiseVendorKpiSourceDisputeInput): Promise<VendorKpiSourceDispute> {
  const p = RaiseVendorKpiSourceDisputeInputSchema.parse(input);
  const data = await callRpc(client, "raise_vendor_kpi_source_dispute", {
    p_tenant_id: p.tenantId,
    p_vendor_master_id: p.vendorMasterId,
    p_kpi_code: p.kpiCode,
    p_source_id: p.sourceId,
    p_source_label: p.sourceLabel,
    p_reason: p.reason,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorKpiSourceDispute, "raise_vendor_kpi_source_dispute");
}

export async function decideVendorKpiSourceDispute(client: VendorPerformanceMutationRpcClient, input: DecideVendorKpiSourceDisputeInput): Promise<VendorKpiSourceDispute> {
  const p = DecideVendorKpiSourceDisputeInputSchema.parse(input);
  const data = await callRpc(client, "decide_vendor_kpi_source_dispute", {
    p_dispute_id: p.disputeId,
    p_expected_version: p.expectedVersion,
    p_decision: p.decision,
    p_decision_notes: p.decisionNotes,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorKpiSourceDispute, "decide_vendor_kpi_source_dispute");
}

// -- Issues / corrective actions -------------------------------------------------

export async function raiseVendorPerformanceIssue(client: VendorPerformanceMutationRpcClient, input: RaiseVendorPerformanceIssueInput): Promise<VendorPerformanceIssue> {
  const p = RaiseVendorPerformanceIssueInputSchema.parse(input);
  const data = await callRpc(client, "raise_vendor_performance_issue", {
    p_tenant_id: p.tenantId,
    p_vendor_master_id: p.vendorMasterId,
    p_scorecard_id: p.scorecardId,
    p_kpi_code: p.kpiCode,
    p_severity: p.severity,
    p_title: p.title,
    p_description: p.description,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorPerformanceIssue, "raise_vendor_performance_issue");
}

export async function updateVendorPerformanceIssueStatus(client: VendorPerformanceMutationRpcClient, input: UpdateVendorPerformanceIssueStatusInput): Promise<VendorPerformanceIssue> {
  const p = UpdateVendorPerformanceIssueStatusInputSchema.parse(input);
  const data = await callRpc(client, "update_vendor_performance_issue_status", {
    p_issue_id: p.issueId,
    p_expected_version: p.expectedVersion,
    p_status: p.status,
    p_resolution_note: p.resolutionNote,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorPerformanceIssue, "update_vendor_performance_issue_status");
}

export async function addVendorPerformanceCorrectiveAction(client: VendorPerformanceMutationRpcClient, input: AddVendorPerformanceCorrectiveActionInput): Promise<VendorPerformanceCorrectiveAction> {
  const p = AddVendorPerformanceCorrectiveActionInputSchema.parse(input);
  const data = await callRpc(client, "add_vendor_performance_corrective_action", {
    p_issue_id: p.issueId,
    p_description: p.description,
    p_owner_label: p.ownerLabel,
    p_due_date: p.dueDate,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorPerformanceCorrectiveAction, "add_vendor_performance_corrective_action");
}

export async function updateVendorPerformanceCorrectiveActionStatus(client: VendorPerformanceMutationRpcClient, input: UpdateVendorPerformanceCorrectiveActionStatusInput): Promise<VendorPerformanceCorrectiveAction> {
  const p = UpdateVendorPerformanceCorrectiveActionStatusInputSchema.parse(input);
  const data = await callRpc(client, "update_vendor_performance_corrective_action_status", {
    p_action_id: p.actionId,
    p_expected_version: p.expectedVersion,
    p_status: p.status,
    p_completion_note: p.completionNote,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorPerformanceCorrectiveAction, "update_vendor_performance_corrective_action_status");
}

// -- Manual adjustments -------------------------------------------------

export async function requestVendorKpiManualAdjustment(client: VendorPerformanceMutationRpcClient, input: RequestVendorKpiManualAdjustmentInput): Promise<VendorKpiManualAdjustment> {
  const p = RequestVendorKpiManualAdjustmentInputSchema.parse(input);
  const data = await callRpc(client, "request_vendor_kpi_manual_adjustment", {
    p_scorecard_id: p.scorecardId,
    p_kpi_code: p.kpiCode,
    p_adjusted_normalized_score: p.adjustedNormalizedScore,
    p_reason: p.reason,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorKpiManualAdjustment, "request_vendor_kpi_manual_adjustment");
}

export async function decideVendorKpiManualAdjustment(client: VendorPerformanceMutationRpcClient, input: DecideVendorKpiManualAdjustmentInput): Promise<VendorKpiManualAdjustment> {
  const p = DecideVendorKpiManualAdjustmentInputSchema.parse(input);
  const data = await callRpc(client, "decide_vendor_kpi_manual_adjustment", {
    p_adjustment_id: p.adjustmentId,
    p_expected_version: p.expectedVersion,
    p_decision: p.decision,
    p_decision_notes: p.decisionNotes,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorKpiManualAdjustment, "decide_vendor_kpi_manual_adjustment");
}

// -- Governed lifecycle recommendations -------------------------------------------------

export async function evaluateVendorLifecycleRecommendation(client: VendorPerformanceMutationRpcClient, input: EvaluateVendorLifecycleRecommendationInput): Promise<VendorLifecycleRecommendation> {
  const p = EvaluateVendorLifecycleRecommendationInputSchema.parse(input);
  const data = await callRpc(client, "evaluate_vendor_lifecycle_recommendation", {
    p_tenant_id: p.tenantId,
    p_vendor_master_id: p.vendorMasterId,
    p_scorecard_id: p.scorecardId,
    p_override_action: p.overrideAction,
    p_rationale: p.rationale,
    p_idempotency_key: p.idempotencyKey,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorLifecycleRecommendation, "evaluate_vendor_lifecycle_recommendation");
}

/** PRC:Override -- on suspend/blacklist/reactivate, calls straight through to the real PRC-251 vendor lifecycle RPC (server-side, atomic with this decision). */
export async function decideVendorLifecycleRecommendation(client: VendorPerformanceMutationRpcClient, input: DecideVendorLifecycleRecommendationInput): Promise<VendorLifecycleRecommendation> {
  const p = DecideVendorLifecycleRecommendationInputSchema.parse(input);
  const data = await callRpc(client, "decide_vendor_lifecycle_recommendation", {
    p_recommendation_id: p.recommendationId,
    p_expected_version: p.expectedVersion,
    p_decided_action: p.decidedAction,
    p_decision_notes: p.decisionNotes,
    p_evidence_ref: p.evidenceRef,
    p_actor_auth_user_id: p.actorAuthUserId,
    p_actor_label: p.actorLabel,
  });
  return requireRow(data, parseVendorLifecycleRecommendation, "decide_vendor_lifecycle_recommendation");
}
