/**
 * OCR Document Processing queries (IAE-021, Prompt 349). Thin, typed wrappers
 * around app.get_ocr_document_job / app.list_ocr_document_jobs_for_tenant
 * (supabase/migrations/20260806000000_create_intelligence_ocr_document_processing.sql).
 */

import {
  GetOcrDocumentJobInputSchema,
  ListOcrDocumentJobsForTenantInputSchema,
  parseOcrDocumentJobFullDetail,
  parseOcrDocumentJobDetail,
  type GetOcrDocumentJobInput,
  type ListOcrDocumentJobsForTenantInput,
  type OcrDocumentJobFullDetail,
  type OcrDocumentJobDetail,
} from "../contracts/ocr-document/ocr-document.ts";

export interface OcrDocumentQueryRpcClient {
  rpc(fn: "get_ocr_document_job" | "list_ocr_document_jobs_for_tenant", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class OcrDocumentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OcrDocumentQueryError";
  }
}

/** Authority: AI:View. Returns null if the job does not exist (or belongs to a different tenant than p_tenant_id). */
export async function getOcrDocumentJob(client: OcrDocumentQueryRpcClient, input: GetOcrDocumentJobInput): Promise<OcrDocumentJobFullDetail | null> {
  const parsedInput = GetOcrDocumentJobInputSchema.parse(input);
  const { data, error } = await client.rpc("get_ocr_document_job", {
    p_job_id: parsedInput.jobId,
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new OcrDocumentQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseOcrDocumentJobFullDetail(row as Record<string, unknown>);
}

/** Authority: AI:View. */
export async function listOcrDocumentJobsForTenant(client: OcrDocumentQueryRpcClient, input: ListOcrDocumentJobsForTenantInput): Promise<OcrDocumentJobDetail[]> {
  const parsedInput = ListOcrDocumentJobsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_ocr_document_jobs_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_status: parsedInput.status,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new OcrDocumentQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OcrDocumentQueryError("list_ocr_document_jobs_for_tenant returned a non-array result");
  }
  return data.map((row) => parseOcrDocumentJobDetail(row as Record<string, unknown>));
}
