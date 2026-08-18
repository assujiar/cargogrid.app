/**
 * Customer Quote Request attachment upload (CPL-302, CG-S13-CPL-004). Reuses
 * the Platform Document/File Engine (PLT-128) directly -- app.
 * initiate_file_upload, service_role-only -- exactly the same "call the RPC
 * name directly, classify into this capability's own error type" technique
 * server/mutations/document-requirement.ts's own uploadShipmentDocumentFile
 * already established, rather than re-exporting document.ts's own
 * DocumentMutationError.
 *
 * This wrapper does NOT itself authorize the caller against a specific quote
 * request -- that per-record decision (does this identity's own resolved
 * account scope include this exact request, and is it still a draft) is the
 * calling Server Action's own job, using getCustomerQuoteRequest first
 * (anti-enumerating). This function only fixes the two capability-owned
 * constants (documentTypeCode='quote_request_attachment', recordType=
 * 'customer_portal_quote_request') and forwards everything else, mirroring
 * every other domain-owned PLT-128 wrapper in this repository.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { UploadCustomerQuoteRequestAttachmentInputSchema, type UploadCustomerQuoteRequestAttachmentInput } from "../contracts/customer-quote-request/customer-quote-request.ts";
import { parseFile, type File as PlatformFile } from "../contracts/document/document.ts";

export type CustomerQuoteRequestAttachmentMutationRpcClient = Pick<SupabaseClient, "rpc">;

const KNOWN_ATTACHMENT_MUTATION_ERROR_CODES = [
  "file_actor_unauthorized",
  "document_type_not_configured",
  "document_unsafe_filename",
  "document_mime_type_not_allowed",
  "document_file_too_large",
  "document_invalid_classification",
  "document_classification_too_weak",
] as const;
type KnownAttachmentMutationErrorCode = (typeof KNOWN_ATTACHMENT_MUTATION_ERROR_CODES)[number];
export type CustomerQuoteRequestAttachmentMutationErrorCode = KnownAttachmentMutationErrorCode | "mutation_failed";

export class CustomerQuoteRequestAttachmentMutationError extends Error {
  readonly code: CustomerQuoteRequestAttachmentMutationErrorCode;

  constructor(code: CustomerQuoteRequestAttachmentMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerQuoteRequestAttachmentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerQuoteRequestAttachmentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (KNOWN_ATTACHMENT_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAttachmentMutationErrorCode) : "mutation_failed";
}

/**
 * Uploads one attachment's metadata against an existing quote request draft.
 * Requires `client` to be the SERVICE-ROLE client (app.initiate_file_upload
 * is granted to service_role only, never `authenticated`) -- the caller must
 * already have verified, through the ordinary RLS-scoped client, that
 * `actorAuthUserId` genuinely holds this request in scope and that it is
 * still a draft, BEFORE calling this function (see the Server Action).
 * Content bytes are never stored in this database (disclosed, standing
 * PLT-128 constraint, not unique to this capability) -- only filename/MIME/
 * size metadata is captured.
 */
export async function uploadCustomerQuoteRequestAttachment(
  client: CustomerQuoteRequestAttachmentMutationRpcClient,
  input: UploadCustomerQuoteRequestAttachmentInput,
): Promise<PlatformFile> {
  const v = UploadCustomerQuoteRequestAttachmentInputSchema.parse(input);
  const { data, error } = await client.rpc("initiate_file_upload", {
    p_tenant_id: v.tenantId,
    p_document_type_code: "quote_request_attachment",
    p_record_type: "customer_portal_quote_request",
    p_record_id: v.requestId,
    p_original_filename: v.originalFilename,
    p_mime_type: v.mimeType,
    p_size_bytes: v.sizeBytes,
    p_classification: null,
    p_legal_hold: false,
    p_legal_hold_reason: null,
    p_shared_org_unit_ids: [],
    p_customer_account_ref: null,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
  if (error) {
    throw new CustomerQuoteRequestAttachmentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new CustomerQuoteRequestAttachmentMutationError("mutation_failed", "initiate_file_upload returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}
