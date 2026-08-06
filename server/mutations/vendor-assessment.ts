/**
 * Vendor Assessment mutation primitives (PRC-252, CG-S11-PRC-003). Thin, typed
 * wrappers around every template-lifecycle/assessment-lifecycle/finding/
 * corrective-action RPC in
 * supabase/migrations/20260730590000_create_procurement_vendor_assessment.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorAssessmentTemplateDraftInputSchema,
  UpdateVendorAssessmentTemplateDraftInputSchema,
  AddVendorAssessmentTemplateCriterionInputSchema,
  UpdateVendorAssessmentTemplateCriterionInputSchema,
  RemoveVendorAssessmentTemplateCriterionInputSchema,
  PublishVendorAssessmentTemplateInputSchema,
  ArchiveVendorAssessmentTemplateInputSchema,
  StartVendorAssessmentInputSchema,
  RecordVendorAssessmentAnswerInputSchema,
  CalculateVendorAssessmentScoreInputSchema,
  SubmitVendorAssessmentForReviewInputSchema,
  BeginVendorAssessmentReviewInputSchema,
  DecideVendorAssessmentReviewInputSchema,
  AdjustVendorAssessmentScoreInputSchema,
  CloseVendorAssessmentInputSchema,
  StartVendorAssessmentReassessmentInputSchema,
  RaiseVendorAssessmentFindingInputSchema,
  DecideVendorAssessmentFindingInputSchema,
  CreateVendorAssessmentCorrectiveActionInputSchema,
  UpdateVendorAssessmentCorrectiveActionStatusInputSchema,
  parseVendorAssessmentTemplate,
  parseVendorAssessmentTemplateCriterion,
  parseVendorAssessmentMutationResult,
  parseVendorAssessmentAnswer,
  parseVendorAssessmentFinding,
  parseVendorAssessmentCorrectiveAction,
  type CreateVendorAssessmentTemplateDraftInput,
  type UpdateVendorAssessmentTemplateDraftInput,
  type AddVendorAssessmentTemplateCriterionInput,
  type UpdateVendorAssessmentTemplateCriterionInput,
  type RemoveVendorAssessmentTemplateCriterionInput,
  type PublishVendorAssessmentTemplateInput,
  type ArchiveVendorAssessmentTemplateInput,
  type StartVendorAssessmentInput,
  type RecordVendorAssessmentAnswerInput,
  type CalculateVendorAssessmentScoreInput,
  type SubmitVendorAssessmentForReviewInput,
  type BeginVendorAssessmentReviewInput,
  type DecideVendorAssessmentReviewInput,
  type AdjustVendorAssessmentScoreInput,
  type CloseVendorAssessmentInput,
  type StartVendorAssessmentReassessmentInput,
  type RaiseVendorAssessmentFindingInput,
  type DecideVendorAssessmentFindingInput,
  type CreateVendorAssessmentCorrectiveActionInput,
  type UpdateVendorAssessmentCorrectiveActionStatusInput,
  type VendorAssessmentTemplate,
  type VendorAssessmentTemplateCriterion,
  type VendorAssessmentMutationResult,
  type VendorAssessmentAnswer,
  type VendorAssessmentFinding,
  type VendorAssessmentCorrectiveAction,
} from "../contracts/vendor-assessment/vendor-assessment.ts";

export type VendorAssessmentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_ASSESSMENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "invalid_name",
  "invalid_assessment_type",
  "invalid_validity_period",
  "invalid_pass_threshold",
  "invalid_conditional_threshold",
  "invalid_threshold_order",
  "invalid_weight_total",
  "idempotency_key_conflict",
  "vendor_assessment_template_not_found",
  "vendor_assessment_template_not_draft",
  "stale_version",
  "invalid_transition",
  "invalid_criterion",
  "invalid_purpose_tag",
  "invalid_weight",
  "criterion_not_found",
  "template_has_no_criteria",
  "weight_sum_mismatch",
  "superseded_template_not_found",
  "invalid_supersede",
  "active_template_exists",
  "reason_required",
  "vendor_profile_not_found",
  "vendor_blacklisted",
  "self_approval_not_allowed",
  "template_not_published",
  "template_category_mismatch",
  "conflicting_active_assessment",
  "vendor_assessment_not_found",
  "not_assigned_assessor",
  "vendor_assessment_not_editable",
  "criterion_not_in_template",
  "invalid_score",
  "vendor_assessment_closed",
  "missing_required_criteria",
  "invalid_decision",
  "review_already_assigned",
  "invalid_adjusted_score",
  "open_corrective_actions_block_close",
  "predecessor_not_approved",
  "reassessment_type_mismatch",
  "vendor_assessment_not_active",
  "invalid_severity",
  "invalid_finding",
  "finding_not_found",
  "finding_not_open",
  "invalid_corrective_action",
  "corrective_action_not_found",
  "invalid_status",
  "resolution_notes_required",
  "evidence_file_not_found",
  "assessment_evidence_file_mismatch",
  "assessment_unsafe_evidence",
  "invalid_response",
] as const;
type KnownVendorAssessmentMutationErrorCode = (typeof VENDOR_ASSESSMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorAssessmentMutationErrorCode = KnownVendorAssessmentMutationErrorCode | "mutation_failed";

export class VendorAssessmentMutationError extends Error {
  readonly code: VendorAssessmentMutationErrorCode;

  constructor(code: VendorAssessmentMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorAssessmentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorAssessmentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_ASSESSMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorAssessmentMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseTemplateResponse(data: unknown, rpcName: string): VendorAssessmentTemplate {
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorAssessmentTemplate(row);
}

function parseCriterionResponse(data: unknown, rpcName: string): VendorAssessmentTemplateCriterion {
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorAssessmentTemplateCriterion(row);
}

function parseAssessmentResponse(data: unknown, rpcName: string): VendorAssessmentMutationResult {
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorAssessmentMutationResult(row);
}

// --- Template lifecycle ---

export async function createVendorAssessmentTemplateDraft(client: VendorAssessmentMutationRpcClient, input: CreateVendorAssessmentTemplateDraftInput): Promise<VendorAssessmentTemplate> {
  const parsed = CreateVendorAssessmentTemplateDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_assessment_template_draft", {
    p_tenant_id: parsed.tenantId,
    p_vendor_category: parsed.vendorCategory ?? null,
    p_assessment_type: parsed.assessmentType,
    p_name: parsed.name,
    p_description: parsed.description ?? null,
    p_validity_period_days: parsed.validityPeriodDays,
    p_pass_threshold: parsed.passThreshold,
    p_conditional_threshold: parsed.conditionalThreshold,
    p_weight_total_required: parsed.weightTotalRequired ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseTemplateResponse(data, "create_vendor_assessment_template_draft");
}

export async function updateVendorAssessmentTemplateDraft(client: VendorAssessmentMutationRpcClient, input: UpdateVendorAssessmentTemplateDraftInput): Promise<VendorAssessmentTemplate> {
  const parsed = UpdateVendorAssessmentTemplateDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_assessment_template_draft", {
    p_template_version_id: parsed.templateVersionId,
    p_expected_version: parsed.expectedVersion,
    p_vendor_category: parsed.vendorCategory ?? null,
    p_name: parsed.name,
    p_description: parsed.description ?? null,
    p_validity_period_days: parsed.validityPeriodDays,
    p_pass_threshold: parsed.passThreshold,
    p_conditional_threshold: parsed.conditionalThreshold,
    p_weight_total_required: parsed.weightTotalRequired ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseTemplateResponse(data, "update_vendor_assessment_template_draft");
}

export async function addVendorAssessmentTemplateCriterion(client: VendorAssessmentMutationRpcClient, input: AddVendorAssessmentTemplateCriterionInput): Promise<VendorAssessmentTemplateCriterion> {
  const parsed = AddVendorAssessmentTemplateCriterionInputSchema.parse(input);
  const { data, error } = await client.rpc("add_vendor_assessment_template_criterion", {
    p_template_version_id: parsed.templateVersionId,
    p_label: parsed.label,
    p_purpose_tag: parsed.purposeTag ?? null,
    p_weight: parsed.weight,
    p_scoring_guidance: parsed.scoringGuidance ?? null,
    p_display_order: parsed.displayOrder ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseCriterionResponse(data, "add_vendor_assessment_template_criterion");
}

export async function updateVendorAssessmentTemplateCriterion(
  client: VendorAssessmentMutationRpcClient,
  input: UpdateVendorAssessmentTemplateCriterionInput,
): Promise<VendorAssessmentTemplateCriterion> {
  const parsed = UpdateVendorAssessmentTemplateCriterionInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_assessment_template_criterion", {
    p_criterion_id: parsed.criterionId,
    p_expected_version: parsed.expectedVersion,
    p_label: parsed.label,
    p_purpose_tag: parsed.purposeTag ?? null,
    p_weight: parsed.weight,
    p_scoring_guidance: parsed.scoringGuidance ?? null,
    p_display_order: parsed.displayOrder ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseCriterionResponse(data, "update_vendor_assessment_template_criterion");
}

export async function removeVendorAssessmentTemplateCriterion(
  client: VendorAssessmentMutationRpcClient,
  input: RemoveVendorAssessmentTemplateCriterionInput,
): Promise<VendorAssessmentTemplateCriterion> {
  const parsed = RemoveVendorAssessmentTemplateCriterionInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_vendor_assessment_template_criterion", {
    p_criterion_id: parsed.criterionId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseCriterionResponse(data, "remove_vendor_assessment_template_criterion");
}

export async function publishVendorAssessmentTemplate(client: VendorAssessmentMutationRpcClient, input: PublishVendorAssessmentTemplateInput): Promise<VendorAssessmentTemplate> {
  const parsed = PublishVendorAssessmentTemplateInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_vendor_assessment_template", {
    p_template_version_id: parsed.templateVersionId,
    p_expected_version: parsed.expectedVersion,
    p_supersedes_version_id: parsed.supersedesVersionId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseTemplateResponse(data, "publish_vendor_assessment_template");
}

export async function archiveVendorAssessmentTemplate(client: VendorAssessmentMutationRpcClient, input: ArchiveVendorAssessmentTemplateInput): Promise<VendorAssessmentTemplate> {
  const parsed = ArchiveVendorAssessmentTemplateInputSchema.parse(input);
  const { data, error } = await client.rpc("archive_vendor_assessment_template", {
    p_template_version_id: parsed.templateVersionId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseTemplateResponse(data, "archive_vendor_assessment_template");
}

// --- Assessment lifecycle ---

export async function startVendorAssessment(client: VendorAssessmentMutationRpcClient, input: StartVendorAssessmentInput): Promise<VendorAssessmentMutationResult> {
  const parsed = StartVendorAssessmentInputSchema.parse(input);
  const { data, error } = await client.rpc("start_vendor_assessment", {
    p_vendor_master_record_id: parsed.vendorMasterRecordId,
    p_template_version_id: parsed.templateVersionId,
    p_reviewer_auth_user_id: parsed.reviewerAuthUserId ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "start_vendor_assessment");
}

export async function recordVendorAssessmentAnswer(client: VendorAssessmentMutationRpcClient, input: RecordVendorAssessmentAnswerInput): Promise<VendorAssessmentAnswer> {
  const parsed = RecordVendorAssessmentAnswerInputSchema.parse(input);
  const { data, error } = await client.rpc("record_vendor_assessment_answer", {
    p_assessment_id: parsed.assessmentId,
    p_criterion_id: parsed.criterionId,
    p_value: parsed.value ?? null,
    p_score: parsed.score,
    p_evidence_file_id: parsed.evidenceFileId ?? null,
    p_notes: parsed.notes ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", "record_vendor_assessment_answer returned no row");
  return parseVendorAssessmentAnswer(row);
}

export async function calculateVendorAssessmentScore(client: VendorAssessmentMutationRpcClient, input: CalculateVendorAssessmentScoreInput): Promise<VendorAssessmentMutationResult> {
  const parsed = CalculateVendorAssessmentScoreInputSchema.parse(input);
  const { data, error } = await client.rpc("calculate_vendor_assessment_score", {
    p_assessment_id: parsed.assessmentId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "calculate_vendor_assessment_score");
}

export async function submitVendorAssessmentForReview(client: VendorAssessmentMutationRpcClient, input: SubmitVendorAssessmentForReviewInput): Promise<VendorAssessmentMutationResult> {
  const parsed = SubmitVendorAssessmentForReviewInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_vendor_assessment_for_review", {
    p_assessment_id: parsed.assessmentId,
    p_expected_version: parsed.expectedVersion,
    p_reviewer_auth_user_id: parsed.reviewerAuthUserId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "submit_vendor_assessment_for_review");
}

export async function beginVendorAssessmentReview(client: VendorAssessmentMutationRpcClient, input: BeginVendorAssessmentReviewInput): Promise<VendorAssessmentMutationResult> {
  const parsed = BeginVendorAssessmentReviewInputSchema.parse(input);
  const { data, error } = await client.rpc("begin_vendor_assessment_review", {
    p_assessment_id: parsed.assessmentId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "begin_vendor_assessment_review");
}

export async function decideVendorAssessmentReview(client: VendorAssessmentMutationRpcClient, input: DecideVendorAssessmentReviewInput): Promise<VendorAssessmentMutationResult> {
  const parsed = DecideVendorAssessmentReviewInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_assessment_review", {
    p_assessment_id: parsed.assessmentId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "decide_vendor_assessment_review");
}

export async function adjustVendorAssessmentScore(client: VendorAssessmentMutationRpcClient, input: AdjustVendorAssessmentScoreInput): Promise<VendorAssessmentMutationResult> {
  const parsed = AdjustVendorAssessmentScoreInputSchema.parse(input);
  const { data, error } = await client.rpc("adjust_vendor_assessment_score", {
    p_assessment_id: parsed.assessmentId,
    p_expected_version: parsed.expectedVersion,
    p_adjusted_score: parsed.adjustedScore,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "adjust_vendor_assessment_score");
}

export async function closeVendorAssessment(client: VendorAssessmentMutationRpcClient, input: CloseVendorAssessmentInput): Promise<VendorAssessmentMutationResult> {
  const parsed = CloseVendorAssessmentInputSchema.parse(input);
  const { data, error } = await client.rpc("close_vendor_assessment", {
    p_assessment_id: parsed.assessmentId,
    p_expected_version: parsed.expectedVersion,
    p_override_reason: parsed.overrideReason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "close_vendor_assessment");
}

export async function startVendorAssessmentReassessment(client: VendorAssessmentMutationRpcClient, input: StartVendorAssessmentReassessmentInput): Promise<VendorAssessmentMutationResult> {
  const parsed = StartVendorAssessmentReassessmentInputSchema.parse(input);
  const { data, error } = await client.rpc("start_vendor_assessment_reassessment", {
    p_predecessor_assessment_id: parsed.predecessorAssessmentId,
    p_template_version_id: parsed.templateVersionId,
    p_reviewer_auth_user_id: parsed.reviewerAuthUserId ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  return parseAssessmentResponse(data, "start_vendor_assessment_reassessment");
}

// --- Findings and corrective actions ---

export async function raiseVendorAssessmentFinding(client: VendorAssessmentMutationRpcClient, input: RaiseVendorAssessmentFindingInput): Promise<VendorAssessmentFinding> {
  const parsed = RaiseVendorAssessmentFindingInputSchema.parse(input);
  const { data, error } = await client.rpc("raise_vendor_assessment_finding", {
    p_assessment_id: parsed.assessmentId,
    p_severity: parsed.severity,
    p_description: parsed.description,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", "raise_vendor_assessment_finding returned no row");
  return parseVendorAssessmentFinding(row);
}

export async function decideVendorAssessmentFinding(client: VendorAssessmentMutationRpcClient, input: DecideVendorAssessmentFindingInput): Promise<VendorAssessmentFinding> {
  const parsed = DecideVendorAssessmentFindingInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_assessment_finding", {
    p_finding_id: parsed.findingId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", "decide_vendor_assessment_finding returned no row");
  return parseVendorAssessmentFinding(row);
}

export async function createVendorAssessmentCorrectiveAction(
  client: VendorAssessmentMutationRpcClient,
  input: CreateVendorAssessmentCorrectiveActionInput,
): Promise<VendorAssessmentCorrectiveAction> {
  const parsed = CreateVendorAssessmentCorrectiveActionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_assessment_corrective_action", {
    p_finding_id: parsed.findingId,
    p_description: parsed.description,
    p_due_date: parsed.dueDate ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", "create_vendor_assessment_corrective_action returned no row");
  return parseVendorAssessmentCorrectiveAction(row);
}

export async function updateVendorAssessmentCorrectiveActionStatus(
  client: VendorAssessmentMutationRpcClient,
  input: UpdateVendorAssessmentCorrectiveActionStatusInput,
): Promise<VendorAssessmentCorrectiveAction> {
  const parsed = UpdateVendorAssessmentCorrectiveActionStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_assessment_corrective_action_status", {
    p_corrective_action_id: parsed.correctiveActionId,
    p_expected_version: parsed.expectedVersion,
    p_new_status: parsed.newStatus,
    p_resolution_notes: parsed.resolutionNotes ?? null,
    p_resolved_evidence_file_id: parsed.resolvedEvidenceFileId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorAssessmentMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorAssessmentMutationError("invalid_response", "update_vendor_assessment_corrective_action_status returned no row");
  return parseVendorAssessmentCorrectiveAction(row);
}
