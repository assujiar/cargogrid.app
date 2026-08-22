/**
 * OCR Document Processing mutation primitives (IAE-021, Prompt 349). Thin,
 * typed wrappers around app.submit_ocr_document_job / app.record_ocr_document_job_outcome /
 * app.save_ocr_document_job_correction / app.dismiss_ocr_document_job /
 * app.apply_ocr_document_job_to_ticket
 * (supabase/migrations/20260806000000_create_intelligence_ocr_document_processing.sql).
 */

import {
  SubmitOcrDocumentJobInputSchema,
  RecordOcrDocumentJobOutcomeInputSchema,
  SaveOcrDocumentJobCorrectionInputSchema,
  DismissOcrDocumentJobInputSchema,
  ApplyOcrDocumentJobToTicketInputSchema,
  parseOcrDocumentJob,
  type SubmitOcrDocumentJobInput,
  type RecordOcrDocumentJobOutcomeInput,
  type SaveOcrDocumentJobCorrectionInput,
  type DismissOcrDocumentJobInput,
  type ApplyOcrDocumentJobToTicketInput,
  type OcrDocumentJob,
} from "../contracts/ocr-document/ocr-document.ts";

export interface OcrDocumentMutationRpcClient {
  rpc(
    fn: "submit_ocr_document_job" | "record_ocr_document_job_outcome" | "save_ocr_document_job_correction" | "dismiss_ocr_document_job" | "apply_ocr_document_job_to_ticket",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const OCR_DOCUMENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "ocr_document_job_invalid_type_hint",
  "idempotency_key_conflict",
  "ocr_document_job_file_not_found",
  "ocr_document_job_file_not_active",
  "ocr_document_job_file_not_scanned",
  "ocr_document_job_not_found",
  "ocr_document_job_outcome_already_recorded",
  "ocr_document_job_not_pending",
  "ai_governed_request_not_found",
  "ocr_document_job_request_tenant_mismatch",
  "ocr_document_job_wrong_feature",
  "ocr_document_job_correlation_mismatch",
  "ocr_document_job_request_not_completed",
  "ocr_document_job_not_reviewable",
  "ocr_document_job_invalid_correction_shape",
  "ocr_document_job_dismiss_reason_required",
  "ocr_document_job_not_dismissible",
  "ocr_document_job_not_applyable",
  "ocr_document_job_subject_required",
  "ocr_document_job_body_required",
  "ocr_document_job_low_confidence_override_required",
  "ocr_document_job_invalid_limit",
] as const;
type KnownOcrDocumentMutationErrorCode = (typeof OCR_DOCUMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type OcrDocumentMutationErrorCode = KnownOcrDocumentMutationErrorCode | "mutation_failed" | "invalid_response";

export class OcrDocumentMutationError extends Error {
  readonly code: OcrDocumentMutationErrorCode;

  constructor(code: OcrDocumentMutationErrorCode, message: string) {
    super(message);
    this.name = "OcrDocumentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): OcrDocumentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (OCR_DOCUMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownOcrDocumentMutationErrorCode) : "mutation_failed";
}

function parseJobResponse(fnName: string, data: unknown, error: { message: string } | null): OcrDocumentJob {
  if (error) {
    throw new OcrDocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new OcrDocumentMutationError("invalid_response", `${fnName} returned no row`);
  }
  return parseOcrDocumentJob(data as Record<string, unknown>);
}

/** The entry point the TS orchestration client calls before dispatching a real governed AI request. Idempotent per (tenant, idempotency key). */
export async function submitOcrDocumentJob(client: OcrDocumentMutationRpcClient, input: SubmitOcrDocumentJobInput): Promise<OcrDocumentJob> {
  const parsedInput = SubmitOcrDocumentJobInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_ocr_document_job", {
    p_tenant_id: parsedInput.tenantId,
    p_file_id: parsedInput.fileId,
    p_document_type_hint: parsedInput.documentTypeHint,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseJobResponse("submit_ocr_document_job", data, error);
}

/** Called by the AI-dispatch orchestration client AFTER a real dispatchAiGovernedRequest round trip, regardless of outcome. Idempotent per (job, governed request). */
export async function recordOcrDocumentJobOutcome(client: OcrDocumentMutationRpcClient, input: RecordOcrDocumentJobOutcomeInput): Promise<OcrDocumentJob> {
  const parsedInput = RecordOcrDocumentJobOutcomeInputSchema.parse(input);
  const { data, error } = await client.rpc("record_ocr_document_job_outcome", {
    p_job_id: parsedInput.jobId,
    p_ai_governed_request_id: parsedInput.aiGovernedRequestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseJobResponse("record_ocr_document_job_outcome", data, error);
}

/** Bounded scratch review state -- never read back as trusted input by apply_ocr_document_job_to_ticket. */
export async function saveOcrDocumentJobCorrection(client: OcrDocumentMutationRpcClient, input: SaveOcrDocumentJobCorrectionInput): Promise<OcrDocumentJob> {
  const parsedInput = SaveOcrDocumentJobCorrectionInputSchema.parse(input);
  const { data, error } = await client.rpc("save_ocr_document_job_correction", {
    p_job_id: parsedInput.jobId,
    p_tenant_id: parsedInput.tenantId,
    p_corrected_fields: parsedInput.correctedFields,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseJobResponse("save_ocr_document_job_correction", data, error);
}

/** Atomic pending/extracted/failed/reviewed-only transition. */
export async function dismissOcrDocumentJob(client: OcrDocumentMutationRpcClient, input: DismissOcrDocumentJobInput): Promise<OcrDocumentJob> {
  const parsedInput = DismissOcrDocumentJobInputSchema.parse(input);
  const { data, error } = await client.rpc("dismiss_ocr_document_job", {
    p_job_id: parsedInput.jobId,
    p_tenant_id: parsedInput.tenantId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseJobResponse("dismiss_ocr_document_job", data, error);
}

/**
 * The ONLY path from an OCR job into a real domain table. Never reads the
 * governed request's own output_payload -- every applied field is an
 * explicit, human-typed parameter. Low confidence requires AI:Approve plus a
 * non-empty override reason.
 */
export async function applyOcrDocumentJobToTicket(client: OcrDocumentMutationRpcClient, input: ApplyOcrDocumentJobToTicketInput): Promise<OcrDocumentJob> {
  const parsedInput = ApplyOcrDocumentJobToTicketInputSchema.parse(input);
  const { data, error } = await client.rpc("apply_ocr_document_job_to_ticket", {
    p_job_id: parsedInput.jobId,
    p_tenant_id: parsedInput.tenantId,
    p_requester_employee_id: parsedInput.requesterEmployeeId,
    p_category_id: parsedInput.categoryId,
    p_queue_id: parsedInput.queueId,
    p_priority: parsedInput.priority,
    p_subject: parsedInput.subject,
    p_body: parsedInput.body,
    p_low_confidence_override_reason: parsedInput.lowConfidenceOverrideReason ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  return parseJobResponse("apply_ocr_document_job_to_ticket", data, error);
}
