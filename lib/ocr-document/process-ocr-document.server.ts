/**
 * OCR document extraction orchestration (IAE-021, Prompt 349). The SECOND
 * real consumer of IAE-019's own `dispatchAiGovernedRequest` -- reused
 * completely unmodified (migration design decision 6). This module's only
 * job is to build a prompt from the caller-supplied file metadata (never
 * file content bytes -- no live storage/OCR provider exists in this
 * repository, mirroring app.files' own disclosed "content bytes are never
 * stored" posture), dispatch it, and sync the linked
 * app.ocr_document_jobs row to the real outcome either way. It never writes
 * to any domain table itself -- that only ever happens later, when a human
 * explicitly calls `applyOcrDocumentJobToTicket`
 * (server/mutations/ocr-document.ts) with their own reviewed field values.
 *
 * Unlike generateAiQuotationSuggestion (IAE-020), a failed dispatch is NOT
 * a dead end here -- app.ocr_document_jobs has its own `failed` terminal
 * status precisely for this, so record_ocr_document_job_outcome is always
 * called, regardless of dispatch.success.
 *
 * Must be called with a service-role client: dispatchAiGovernedRequest's own
 * internal record_ai_governed_request_outcome call is granted to
 * service_role only (IAE-019). This module takes file metadata as explicit
 * parameters rather than reading it back from the database itself, so it
 * needs no session-scoped/explicit-actor file read of its own.
 */

import { recordOcrDocumentJobOutcome, type OcrDocumentMutationRpcClient } from "../../server/mutations/ocr-document.ts";
import type { OcrDocumentJob, OcrDocumentJobTypeHint } from "../../server/contracts/ocr-document/ocr-document.ts";
import { dispatchAiGovernedRequest, type DispatchAiGovernedRequestRpcClient, type AiGovernanceDispatchUrlSafetyChecker } from "../ai-governance/dispatch-ai-governed-request.server.ts";

export type ProcessOcrDocumentJobClient = DispatchAiGovernedRequestRpcClient & OcrDocumentMutationRpcClient;

export interface ProcessOcrDocumentJobOptions {
  readonly tenantId: string;
  readonly jobId: string;
  readonly fileId: string;
  readonly documentTypeHint: OcrDocumentJobTypeHint;
  readonly originalFilename: string;
  readonly mimeType: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export interface ProcessOcrDocumentJobResult {
  readonly requestId: string;
  readonly success: boolean;
  readonly job: OcrDocumentJob;
  readonly errorMessage: string | null;
}

/**
 * Real, synchronous end-to-end flow: build a metadata-only prompt -> dispatch
 * -> sync the job's own status either way. Never throws for a delivery-side
 * failure (no connection, HTTP error, low confidence, etc.) --
 * dispatchAiGovernedRequest itself already turns those into a real, recorded
 * `failed` outcome and a `success: false` result, which this function passes
 * through after syncing the job to its own terminal `failed` status. Throws
 * only for whatever dispatchAiGovernedRequest itself still throws for (no
 * active connection configured at all) or a genuine job-state precondition
 * failure surfaced by record_ocr_document_job_outcome (e.g. the job was
 * already dismissed by a reviewer before this call ran).
 */
export async function processOcrDocumentJob(client: ProcessOcrDocumentJobClient, options: ProcessOcrDocumentJobOptions, checkUrlSafety?: AiGovernanceDispatchUrlSafetyChecker): Promise<ProcessOcrDocumentJobResult> {
  const { tenantId, jobId, fileId, documentTypeHint, originalFilename, mimeType, actorAuthUserId, actorLabel } = options;

  const promptPayload: Record<string, unknown> = {
    file: { id: fileId, originalFilename, mimeType },
    documentTypeHint,
  };

  const dispatch = await dispatchAiGovernedRequest(
    client,
    {
      tenantId,
      actorAuthUserId,
      actorLabel,
      featureCode: "ocr_document_extraction",
      correlationRecordType: "file",
      correlationRecordId: fileId,
      promptPayload,
    },
    checkUrlSafety,
  );

  const job = await recordOcrDocumentJobOutcome(client, {
    jobId,
    aiGovernedRequestId: dispatch.requestId,
    actorAuthUserId,
    actorLabel,
  });

  return { requestId: dispatch.requestId, success: dispatch.success, job, errorMessage: dispatch.errorMessage };
}
