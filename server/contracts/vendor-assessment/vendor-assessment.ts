/**
 * Vendor Assessment contract (PRC-252, CG-S11-PRC-003). Mirrors
 * supabase/migrations/20260730590000_create_procurement_vendor_assessment.sql's
 * app.vendor_assessment_templates/app.vendor_assessment_template_criteria/
 * app.vendor_assessments/app.vendor_assessment_answers/
 * app.vendor_assessment_findings/app.vendor_assessment_corrective_actions shapes and
 * their RPCs. Follows the exact directory convention PRC-251 (vendor-profile)
 * established: Zod schemas here, list/read projections in
 * server/queries/vendor-assessment.ts, RPC-calling mutation wrappers with an
 * enumerated error-code type in server/mutations/vendor-assessment.ts.
 *
 * app.vendor_assessments.vendor_master_record_id references
 * app.vendor_profiles.master_record_id (PRC-251) -- the single canonical vendor
 * identity (ADR-0020). This capability never mutates
 * app.vendor_profiles.lifecycle_status.
 */

import { z } from "zod";

export const VENDOR_ASSESSMENT_TYPES = ["initial", "periodic", "incident", "financial", "operational", "safety"] as const;
export const VendorAssessmentTypeSchema = z.enum(VENDOR_ASSESSMENT_TYPES);
export type VendorAssessmentType = z.infer<typeof VendorAssessmentTypeSchema>;

export const VENDOR_ASSESSMENT_TEMPLATE_STATUSES = ["draft", "published", "archived"] as const;
export const VendorAssessmentTemplateStatusSchema = z.enum(VENDOR_ASSESSMENT_TEMPLATE_STATUSES);
export type VendorAssessmentTemplateStatus = z.infer<typeof VendorAssessmentTemplateStatusSchema>;

export const VENDOR_ASSESSMENT_STATUSES = ["draft", "in_progress", "submitted", "under_review", "approved", "rejected", "closed"] as const;
export const VendorAssessmentStatusSchema = z.enum(VENDOR_ASSESSMENT_STATUSES);
export type VendorAssessmentStatus = z.infer<typeof VendorAssessmentStatusSchema>;

export const VENDOR_ASSESSMENT_SCORE_BANDS = ["pass", "conditional", "fail"] as const;
export const VendorAssessmentScoreBandSchema = z.enum(VENDOR_ASSESSMENT_SCORE_BANDS);
export type VendorAssessmentScoreBand = z.infer<typeof VendorAssessmentScoreBandSchema>;

export const VENDOR_ASSESSMENT_PURPOSE_TAGS = ["financial", "safety", "operational", "compliance"] as const;
export const VendorAssessmentPurposeTagSchema = z.enum(VENDOR_ASSESSMENT_PURPOSE_TAGS);
export type VendorAssessmentPurposeTag = z.infer<typeof VendorAssessmentPurposeTagSchema>;

export const VENDOR_ASSESSMENT_REVIEW_DECISIONS = ["approve", "reject"] as const;
export const VendorAssessmentReviewDecisionSchema = z.enum(VENDOR_ASSESSMENT_REVIEW_DECISIONS);
export type VendorAssessmentReviewDecision = z.infer<typeof VendorAssessmentReviewDecisionSchema>;

export const VENDOR_ASSESSMENT_FINDING_SEVERITIES = ["low", "medium", "high", "critical"] as const;
export const VendorAssessmentFindingSeveritySchema = z.enum(VENDOR_ASSESSMENT_FINDING_SEVERITIES);
export type VendorAssessmentFindingSeverity = z.infer<typeof VendorAssessmentFindingSeveritySchema>;

export const VENDOR_ASSESSMENT_FINDING_STATUSES = ["open", "resolved", "waived"] as const;
export const VendorAssessmentFindingStatusSchema = z.enum(VENDOR_ASSESSMENT_FINDING_STATUSES);
export type VendorAssessmentFindingStatus = z.infer<typeof VendorAssessmentFindingStatusSchema>;

export const VENDOR_ASSESSMENT_FINDING_DECISIONS = ["resolved", "waived"] as const;
export const VendorAssessmentFindingDecisionSchema = z.enum(VENDOR_ASSESSMENT_FINDING_DECISIONS);
export type VendorAssessmentFindingDecision = z.infer<typeof VendorAssessmentFindingDecisionSchema>;

export const VENDOR_ASSESSMENT_CORRECTIVE_ACTION_STATUSES = ["open", "completed", "overdue", "waived"] as const;
export const VendorAssessmentCorrectiveActionStatusSchema = z.enum(VENDOR_ASSESSMENT_CORRECTIVE_ACTION_STATUSES);
export type VendorAssessmentCorrectiveActionStatus = z.infer<typeof VendorAssessmentCorrectiveActionStatusSchema>;

// --- Core rows ---

export const VendorAssessmentTemplateSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorCategory: z.string().nullable(),
  assessmentType: VendorAssessmentTypeSchema,
  name: z.string(),
  description: z.string().nullable(),
  validityPeriodDays: z.number().int().positive(),
  passThreshold: z.number(),
  conditionalThreshold: z.number(),
  weightTotalRequired: z.number(),
  status: VendorAssessmentTemplateStatusSchema,
  supersedesVersionId: z.string().uuid().nullable(),
  effectiveFrom: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  criterionCount: z.number().int().optional(),
});
export type VendorAssessmentTemplate = z.infer<typeof VendorAssessmentTemplateSchema>;

export function parseVendorAssessmentTemplate(row: Record<string, unknown>): VendorAssessmentTemplate {
  return VendorAssessmentTemplateSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorCategory: row.vendor_category ?? null,
    assessmentType: row.assessment_type,
    name: row.name,
    description: row.description ?? null,
    validityPeriodDays: row.validity_period_days,
    passThreshold: Number(row.pass_threshold),
    conditionalThreshold: Number(row.conditional_threshold),
    weightTotalRequired: Number(row.weight_total_required),
    status: row.status,
    supersedesVersionId: row.supersedes_version_id ?? null,
    effectiveFrom: row.effective_from,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    criterionCount: row.criterion_count === undefined || row.criterion_count === null ? undefined : Number(row.criterion_count),
  });
}

export const VendorAssessmentTemplateCriterionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  templateVersionId: z.string().uuid(),
  label: z.string(),
  purposeTag: VendorAssessmentPurposeTagSchema,
  weight: z.number(),
  scoringGuidance: z.string().nullable(),
  displayOrder: z.number().int(),
  status: z.enum(["active", "removed"]),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorAssessmentTemplateCriterion = z.infer<typeof VendorAssessmentTemplateCriterionSchema>;

export function parseVendorAssessmentTemplateCriterion(row: Record<string, unknown>): VendorAssessmentTemplateCriterion {
  return VendorAssessmentTemplateCriterionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    templateVersionId: row.template_version_id,
    label: row.label,
    purposeTag: row.purpose_tag,
    weight: Number(row.weight),
    scoringGuidance: row.scoring_guidance ?? null,
    displayOrder: row.display_order,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Raw app.vendor_assessments row, returned by every mutation RPC. */
export const VendorAssessmentMutationResultSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  templateVersionId: z.string().uuid(),
  assessmentType: VendorAssessmentTypeSchema,
  status: VendorAssessmentStatusSchema,
  assessorAuthUserId: z.string().uuid(),
  reviewerAuthUserId: z.string().uuid().nullable(),
  calculatedScore: z.number().nullable(),
  scoreBand: VendorAssessmentScoreBandSchema.nullable(),
  adjustedScore: z.number().nullable(),
  adjustmentReason: z.string().nullable(),
  adjustedBy: z.string().nullable(),
  adjustedAt: z.string().nullable(),
  submittedAt: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decisionReason: z.string().nullable(),
  expiryDate: z.string().nullable(),
  predecessorAssessmentId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorAssessmentMutationResult = z.infer<typeof VendorAssessmentMutationResultSchema>;

export function parseVendorAssessmentMutationResult(row: Record<string, unknown>): VendorAssessmentMutationResult {
  return VendorAssessmentMutationResultSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    templateVersionId: row.template_version_id,
    assessmentType: row.assessment_type,
    status: row.status,
    assessorAuthUserId: row.assessor_auth_user_id,
    reviewerAuthUserId: row.reviewer_auth_user_id ?? null,
    calculatedScore: row.calculated_score === null || row.calculated_score === undefined ? null : Number(row.calculated_score),
    scoreBand: row.score_band ?? null,
    adjustedScore: row.adjusted_score === null || row.adjusted_score === undefined ? null : Number(row.adjusted_score),
    adjustmentReason: row.adjustment_reason ?? null,
    adjustedBy: row.adjusted_by ?? null,
    adjustedAt: row.adjusted_at ?? null,
    submittedAt: row.submitted_at ?? null,
    decidedAt: row.decided_at ?? null,
    decisionReason: row.decision_reason ?? null,
    expiryDate: row.expiry_date ?? null,
    predecessorAssessmentId: row.predecessor_assessment_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_vendor_assessment's own read projection -- adds the computed reassessmentDue flag, distinct from VendorAssessmentMutationResultSchema (the same read-vs-mutation-response boundary PRC-251 already established). */
export const VendorAssessmentSchema = VendorAssessmentMutationResultSchema.extend({
  reassessmentDue: z.boolean(),
});
export type VendorAssessment = z.infer<typeof VendorAssessmentSchema>;

export function parseVendorAssessment(row: Record<string, unknown>): VendorAssessment {
  return VendorAssessmentSchema.parse({
    ...parseVendorAssessmentMutationResult(row),
    reassessmentDue: Boolean(row.reassessment_due),
  });
}

export const VendorAssessmentAnswerSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  assessmentId: z.string().uuid(),
  criterionId: z.string().uuid(),
  value: z.string().nullable(),
  score: z.number(),
  evidenceFileId: z.string().uuid().nullable(),
  notes: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorAssessmentAnswer = z.infer<typeof VendorAssessmentAnswerSchema>;

export function parseVendorAssessmentAnswer(row: Record<string, unknown>): VendorAssessmentAnswer {
  return VendorAssessmentAnswerSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    assessmentId: row.assessment_id,
    criterionId: row.criterion_id,
    value: row.value ?? null,
    score: Number(row.score),
    evidenceFileId: row.evidence_file_id ?? null,
    notes: row.notes ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_vendor_assessment_score_breakdown's own row -- the explainable-scoring projection. value/notes/evidenceFileId may be null either because unanswered or because purpose_tag='financial' masking applied (PRC:View cost) -- all three are masked together. */
export const VendorAssessmentScoreBreakdownRowSchema = z.object({
  criterionId: z.string().uuid(),
  label: z.string(),
  purposeTag: VendorAssessmentPurposeTagSchema,
  weight: z.number(),
  answerScore: z.number().nullable(),
  contribution: z.number(),
  value: z.string().nullable(),
  notes: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  answered: z.boolean(),
});
export type VendorAssessmentScoreBreakdownRow = z.infer<typeof VendorAssessmentScoreBreakdownRowSchema>;

export function parseVendorAssessmentScoreBreakdownRow(row: Record<string, unknown>): VendorAssessmentScoreBreakdownRow {
  return VendorAssessmentScoreBreakdownRowSchema.parse({
    criterionId: row.criterion_id,
    label: row.label,
    purposeTag: row.purpose_tag,
    weight: Number(row.weight),
    answerScore: row.answer_score === null || row.answer_score === undefined ? null : Number(row.answer_score),
    contribution: Number(row.contribution),
    value: row.value ?? null,
    notes: row.notes ?? null,
    evidenceFileId: row.evidence_file_id ?? null,
    answered: Boolean(row.answered),
  });
}

export const VendorAssessmentFindingSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  assessmentId: z.string().uuid(),
  severity: VendorAssessmentFindingSeveritySchema,
  description: z.string(),
  status: VendorAssessmentFindingStatusSchema,
  resolutionReason: z.string().nullable(),
  resolvedBy: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorAssessmentFinding = z.infer<typeof VendorAssessmentFindingSchema>;

export function parseVendorAssessmentFinding(row: Record<string, unknown>): VendorAssessmentFinding {
  return VendorAssessmentFindingSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    assessmentId: row.assessment_id,
    severity: row.severity,
    description: row.description,
    status: row.status,
    resolutionReason: row.resolution_reason ?? null,
    resolvedBy: row.resolved_by ?? null,
    resolvedAt: row.resolved_at ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorAssessmentCorrectiveActionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  findingId: z.string().uuid(),
  assessmentId: z.string().uuid(),
  description: z.string(),
  dueDate: z.string().nullable(),
  status: VendorAssessmentCorrectiveActionStatusSchema,
  resolutionNotes: z.string().nullable(),
  resolvedEvidenceFileId: z.string().uuid().nullable(),
  resolvedBy: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorAssessmentCorrectiveAction = z.infer<typeof VendorAssessmentCorrectiveActionSchema>;

export function parseVendorAssessmentCorrectiveAction(row: Record<string, unknown>): VendorAssessmentCorrectiveAction {
  return VendorAssessmentCorrectiveActionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    findingId: row.finding_id,
    assessmentId: row.assessment_id,
    description: row.description,
    dueDate: row.due_date ?? null,
    status: row.status,
    resolutionNotes: row.resolution_notes ?? null,
    resolvedEvidenceFileId: row.resolved_evidence_file_id ?? null,
    resolvedBy: row.resolved_by ?? null,
    resolvedAt: row.resolved_at ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_vendor_current_assessment_status's own row -- one per assessment_type, the downstream-composable read (prompt's own "Downstream" scope note). */
export const VendorCurrentAssessmentStatusRowSchema = z.object({
  assessmentType: VendorAssessmentTypeSchema,
  assessmentId: z.string().uuid(),
  status: VendorAssessmentStatusSchema,
  calculatedScore: z.number().nullable(),
  adjustedScore: z.number().nullable(),
  scoreBand: VendorAssessmentScoreBandSchema.nullable(),
  decidedAt: z.string().nullable(),
  expiryDate: z.string().nullable(),
  reassessmentDue: z.boolean(),
});
export type VendorCurrentAssessmentStatusRow = z.infer<typeof VendorCurrentAssessmentStatusRowSchema>;

export function parseVendorCurrentAssessmentStatusRow(row: Record<string, unknown>): VendorCurrentAssessmentStatusRow {
  return VendorCurrentAssessmentStatusRowSchema.parse({
    assessmentType: row.assessment_type,
    assessmentId: row.assessment_id,
    status: row.status,
    calculatedScore: row.calculated_score === null || row.calculated_score === undefined ? null : Number(row.calculated_score),
    adjustedScore: row.adjusted_score === null || row.adjusted_score === undefined ? null : Number(row.adjusted_score),
    scoreBand: row.score_band ?? null,
    decidedAt: row.decided_at ?? null,
    expiryDate: row.expiry_date ?? null,
    reassessmentDue: Boolean(row.reassessment_due),
  });
}

// --- Mutation inputs ---

const actorFields = {
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
};

export const CreateVendorAssessmentTemplateDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorCategory: z.string().nullable().optional(),
  assessmentType: VendorAssessmentTypeSchema,
  name: z.string().min(1),
  description: z.string().nullable().optional(),
  validityPeriodDays: z.number().int().positive(),
  passThreshold: z.number().min(0).max(100),
  conditionalThreshold: z.number().min(0).max(100),
  // Pinned to exactly 100 (DB CHECK vendor_assessment_templates_weight_total_check,
  // adversarial-review fix): app._compute_vendor_assessment_score's own formula
  // hardcodes a 100-point denominator, so any other total either crashes the
  // calculated_score range CHECK or makes pass_threshold mathematically unreachable.
  weightTotalRequired: z.literal(100).nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type CreateVendorAssessmentTemplateDraftInput = z.infer<typeof CreateVendorAssessmentTemplateDraftInputSchema>;

export const UpdateVendorAssessmentTemplateDraftInputSchema = z.object({
  templateVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  vendorCategory: z.string().nullable().optional(),
  name: z.string().min(1),
  description: z.string().nullable().optional(),
  validityPeriodDays: z.number().int().positive(),
  passThreshold: z.number().min(0).max(100),
  conditionalThreshold: z.number().min(0).max(100),
  // Pinned to exactly 100 (DB CHECK vendor_assessment_templates_weight_total_check,
  // adversarial-review fix): app._compute_vendor_assessment_score's own formula
  // hardcodes a 100-point denominator, so any other total either crashes the
  // calculated_score range CHECK or makes pass_threshold mathematically unreachable.
  weightTotalRequired: z.literal(100).nullable().optional(),
  ...actorFields,
});
export type UpdateVendorAssessmentTemplateDraftInput = z.infer<typeof UpdateVendorAssessmentTemplateDraftInputSchema>;

export const AddVendorAssessmentTemplateCriterionInputSchema = z.object({
  templateVersionId: z.string().uuid(),
  label: z.string().min(1),
  purposeTag: VendorAssessmentPurposeTagSchema.optional(),
  weight: z.number().positive(),
  scoringGuidance: z.string().nullable().optional(),
  displayOrder: z.number().int().optional(),
  ...actorFields,
});
export type AddVendorAssessmentTemplateCriterionInput = z.infer<typeof AddVendorAssessmentTemplateCriterionInputSchema>;

export const UpdateVendorAssessmentTemplateCriterionInputSchema = z.object({
  criterionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  label: z.string().min(1),
  purposeTag: VendorAssessmentPurposeTagSchema.optional(),
  weight: z.number().positive(),
  scoringGuidance: z.string().nullable().optional(),
  displayOrder: z.number().int().optional(),
  ...actorFields,
});
export type UpdateVendorAssessmentTemplateCriterionInput = z.infer<typeof UpdateVendorAssessmentTemplateCriterionInputSchema>;

export const RemoveVendorAssessmentTemplateCriterionInputSchema = z.object({
  criterionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  ...actorFields,
});
export type RemoveVendorAssessmentTemplateCriterionInput = z.infer<typeof RemoveVendorAssessmentTemplateCriterionInputSchema>;

export const PublishVendorAssessmentTemplateInputSchema = z.object({
  templateVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type PublishVendorAssessmentTemplateInput = z.infer<typeof PublishVendorAssessmentTemplateInputSchema>;

export const ArchiveVendorAssessmentTemplateInputSchema = z.object({
  templateVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  ...actorFields,
});
export type ArchiveVendorAssessmentTemplateInput = z.infer<typeof ArchiveVendorAssessmentTemplateInputSchema>;

export const StartVendorAssessmentInputSchema = z.object({
  vendorMasterRecordId: z.string().uuid(),
  templateVersionId: z.string().uuid(),
  reviewerAuthUserId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type StartVendorAssessmentInput = z.infer<typeof StartVendorAssessmentInputSchema>;

export const RecordVendorAssessmentAnswerInputSchema = z.object({
  assessmentId: z.string().uuid(),
  criterionId: z.string().uuid(),
  value: z.string().nullable().optional(),
  score: z.number().min(0).max(100),
  evidenceFileId: z.string().uuid().nullable().optional(),
  notes: z.string().nullable().optional(),
  ...actorFields,
});
export type RecordVendorAssessmentAnswerInput = z.infer<typeof RecordVendorAssessmentAnswerInputSchema>;

export const CalculateVendorAssessmentScoreInputSchema = z.object({
  assessmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  ...actorFields,
});
export type CalculateVendorAssessmentScoreInput = z.infer<typeof CalculateVendorAssessmentScoreInputSchema>;

export const SubmitVendorAssessmentForReviewInputSchema = z.object({
  assessmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reviewerAuthUserId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type SubmitVendorAssessmentForReviewInput = z.infer<typeof SubmitVendorAssessmentForReviewInputSchema>;

export const BeginVendorAssessmentReviewInputSchema = z.object({
  assessmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  ...actorFields,
});
export type BeginVendorAssessmentReviewInput = z.infer<typeof BeginVendorAssessmentReviewInputSchema>;

export const DecideVendorAssessmentReviewInputSchema = z.object({
  assessmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: VendorAssessmentReviewDecisionSchema,
  reason: z.string().nullable().optional(),
  ...actorFields,
});
export type DecideVendorAssessmentReviewInput = z.infer<typeof DecideVendorAssessmentReviewInputSchema>;

export const AdjustVendorAssessmentScoreInputSchema = z.object({
  assessmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  adjustedScore: z.number().min(0).max(100),
  reason: z.string().min(1),
  ...actorFields,
});
export type AdjustVendorAssessmentScoreInput = z.infer<typeof AdjustVendorAssessmentScoreInputSchema>;

export const CloseVendorAssessmentInputSchema = z.object({
  assessmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  overrideReason: z.string().nullable().optional(),
  ...actorFields,
});
export type CloseVendorAssessmentInput = z.infer<typeof CloseVendorAssessmentInputSchema>;

export const StartVendorAssessmentReassessmentInputSchema = z.object({
  predecessorAssessmentId: z.string().uuid(),
  templateVersionId: z.string().uuid(),
  reviewerAuthUserId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type StartVendorAssessmentReassessmentInput = z.infer<typeof StartVendorAssessmentReassessmentInputSchema>;

export const RaiseVendorAssessmentFindingInputSchema = z.object({
  assessmentId: z.string().uuid(),
  severity: VendorAssessmentFindingSeveritySchema,
  description: z.string().min(1),
  ...actorFields,
});
export type RaiseVendorAssessmentFindingInput = z.infer<typeof RaiseVendorAssessmentFindingInputSchema>;

export const DecideVendorAssessmentFindingInputSchema = z.object({
  findingId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: VendorAssessmentFindingDecisionSchema,
  reason: z.string().min(1),
  ...actorFields,
});
export type DecideVendorAssessmentFindingInput = z.infer<typeof DecideVendorAssessmentFindingInputSchema>;

export const CreateVendorAssessmentCorrectiveActionInputSchema = z.object({
  findingId: z.string().uuid(),
  description: z.string().min(1),
  dueDate: z.string().nullable().optional(),
  ...actorFields,
});
export type CreateVendorAssessmentCorrectiveActionInput = z.infer<typeof CreateVendorAssessmentCorrectiveActionInputSchema>;

export const UpdateVendorAssessmentCorrectiveActionStatusInputSchema = z.object({
  correctiveActionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newStatus: VendorAssessmentCorrectiveActionStatusSchema,
  resolutionNotes: z.string().nullable().optional(),
  resolvedEvidenceFileId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type UpdateVendorAssessmentCorrectiveActionStatusInput = z.infer<typeof UpdateVendorAssessmentCorrectiveActionStatusInputSchema>;
