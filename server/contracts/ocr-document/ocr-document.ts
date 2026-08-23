/**
 * OCR Document Processing contract (IAE-021, Prompt 349). Mirrors
 * supabase/migrations/20260806000000_create_intelligence_ocr_document_processing.sql's
 * app.ocr_document_jobs shape and its submit/record/correct/dismiss/apply/get/list RPCs.
 */

import { z } from "zod";

export const OCR_DOCUMENT_JOB_TYPE_HINTS = ["logistics", "finance", "hr", "ticket", "other"] as const;
export const OcrDocumentJobTypeHintSchema = z.enum(OCR_DOCUMENT_JOB_TYPE_HINTS);
export type OcrDocumentJobTypeHint = z.infer<typeof OcrDocumentJobTypeHintSchema>;

export const OCR_DOCUMENT_JOB_STATUSES = ["pending", "extracted", "failed", "reviewed", "applied", "dismissed"] as const;
export const OcrDocumentJobStatusSchema = z.enum(OCR_DOCUMENT_JOB_STATUSES);
export type OcrDocumentJobStatus = z.infer<typeof OcrDocumentJobStatusSchema>;

/** The raw app.ocr_document_jobs row shape, as returned by submit/record/correct/dismiss/apply. */
export const OcrDocumentJobSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  fileId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid().nullable(),
  documentTypeHint: OcrDocumentJobTypeHintSchema,
  status: OcrDocumentJobStatusSchema,
  reviewerCorrectedFields: z.record(z.string(), z.unknown()).nullable(),
  lowConfidenceOverrideReason: z.string().nullable(),
  appliedTargetType: z.string().nullable(),
  appliedTargetId: z.string().uuid().nullable(),
  dismissReason: z.string().nullable(),
  requestedBy: z.string().nullable(),
  reviewedBy: z.string().nullable(),
  createdAt: z.string(),
  reviewedAt: z.string().nullable(),
  appliedAt: z.string().nullable(),
});
export type OcrDocumentJob = z.infer<typeof OcrDocumentJobSchema>;

export function parseOcrDocumentJob(row: Record<string, unknown>): OcrDocumentJob {
  return OcrDocumentJobSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    fileId: row.file_id,
    aiGovernedRequestId: row.ai_governed_request_id,
    documentTypeHint: row.document_type_hint,
    status: row.status,
    reviewerCorrectedFields: row.reviewer_corrected_fields,
    lowConfidenceOverrideReason: row.low_confidence_override_reason,
    appliedTargetType: row.applied_target_type,
    appliedTargetId: row.applied_target_id,
    dismissReason: row.dismiss_reason,
    requestedBy: row.requested_by,
    reviewedBy: row.reviewed_by,
    createdAt: row.created_at,
    reviewedAt: row.reviewed_at,
    appliedAt: row.applied_at,
  });
}

/** The get/list read-path shape -- joins in the underlying governed request's own evidence (never editable here, IAE-019's own table). */
export const OcrDocumentJobDetailSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  fileId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid().nullable(),
  documentTypeHint: OcrDocumentJobTypeHintSchema,
  status: OcrDocumentJobStatusSchema,
  appliedTargetType: z.string().nullable(),
  appliedTargetId: z.string().uuid().nullable(),
  requestedBy: z.string().nullable(),
  createdAt: z.string(),
  confidenceLabel: z.enum(["high", "medium", "low"]).nullable(),
  requestStatus: z.string().nullable(),
});
export type OcrDocumentJobDetail = z.infer<typeof OcrDocumentJobDetailSchema>;

export function parseOcrDocumentJobDetail(row: Record<string, unknown>): OcrDocumentJobDetail {
  return OcrDocumentJobDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    fileId: row.file_id,
    aiGovernedRequestId: row.ai_governed_request_id,
    documentTypeHint: row.document_type_hint,
    status: row.status,
    appliedTargetType: row.applied_target_type,
    appliedTargetId: row.applied_target_id,
    requestedBy: row.requested_by,
    createdAt: row.created_at,
    confidenceLabel: row.confidence_label,
    requestStatus: row.request_status,
  });
}

/** app.get_ocr_document_job's own wider shape -- includes the real output_payload evidence. */
export const OcrDocumentJobFullDetailSchema = OcrDocumentJobDetailSchema.extend({
  reviewerCorrectedFields: z.record(z.string(), z.unknown()).nullable(),
  lowConfidenceOverrideReason: z.string().nullable(),
  dismissReason: z.string().nullable(),
  reviewedBy: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  appliedAt: z.string().nullable(),
  outputPayload: z.record(z.string(), z.unknown()).nullable(),
  modelVersion: z.string().nullable(),
});
export type OcrDocumentJobFullDetail = z.infer<typeof OcrDocumentJobFullDetailSchema>;

export function parseOcrDocumentJobFullDetail(row: Record<string, unknown>): OcrDocumentJobFullDetail {
  return OcrDocumentJobFullDetailSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    fileId: row.file_id,
    aiGovernedRequestId: row.ai_governed_request_id,
    documentTypeHint: row.document_type_hint,
    status: row.status,
    reviewerCorrectedFields: row.reviewer_corrected_fields,
    lowConfidenceOverrideReason: row.low_confidence_override_reason,
    appliedTargetType: row.applied_target_type,
    appliedTargetId: row.applied_target_id,
    dismissReason: row.dismiss_reason,
    requestedBy: row.requested_by,
    reviewedBy: row.reviewed_by,
    createdAt: row.created_at,
    reviewedAt: row.reviewed_at,
    appliedAt: row.applied_at,
    confidenceLabel: row.confidence_label,
    requestStatus: row.request_status,
    outputPayload: row.output_payload,
    modelVersion: row.model_version,
  });
}

export const SubmitOcrDocumentJobInputSchema = z.object({
  tenantId: z.string().uuid(),
  fileId: z.string().uuid(),
  documentTypeHint: OcrDocumentJobTypeHintSchema,
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitOcrDocumentJobInput = z.input<typeof SubmitOcrDocumentJobInputSchema>;

export const RecordOcrDocumentJobOutcomeInputSchema = z.object({
  jobId: z.string().uuid(),
  aiGovernedRequestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordOcrDocumentJobOutcomeInput = z.input<typeof RecordOcrDocumentJobOutcomeInputSchema>;

export const SaveOcrDocumentJobCorrectionInputSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  correctedFields: z.record(z.string(), z.unknown()),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SaveOcrDocumentJobCorrectionInput = z.input<typeof SaveOcrDocumentJobCorrectionInputSchema>;

export const DismissOcrDocumentJobInputSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DismissOcrDocumentJobInput = z.input<typeof DismissOcrDocumentJobInputSchema>;

export const ApplyOcrDocumentJobToTicketInputSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  requesterEmployeeId: z.string().uuid(),
  categoryId: z.string().uuid(),
  queueId: z.string().uuid(),
  priority: z.enum(["low", "normal", "high", "urgent"]),
  subject: z.string().min(1),
  body: z.string().min(1),
  lowConfidenceOverrideReason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ApplyOcrDocumentJobToTicketInput = z.input<typeof ApplyOcrDocumentJobToTicketInputSchema>;

export const GetOcrDocumentJobInputSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetOcrDocumentJobInput = z.input<typeof GetOcrDocumentJobInputSchema>;

export const ListOcrDocumentJobsForTenantInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  status: OcrDocumentJobStatusSchema.nullable().default(null),
  limit: z.number().int().positive().max(200).default(50),
});
export type ListOcrDocumentJobsForTenantInput = z.input<typeof ListOcrDocumentJobsForTenantInputSchema>;
