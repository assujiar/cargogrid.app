/**
 * Document and file engine mutation primitives (PLT-128, CG-S6-PLT-025). Thin, typed
 * wrappers around app.register_document_type / app.publish_document_type_definition /
 * app.initiate_file_upload / app.record_file_scan_result / app.authorize_file_access /
 * app.create_file_version / app.request_file_deletion / app.set_file_legal_hold
 * (supabase/migrations/20260719140000_create_document_file_engine.sql). Every one of
 * these is service_role-only (see the migration's own grant comment and header) --
 * this capability is server-mediated only, since real signed-URL issuance inherently
 * requires storage credentials only server code holds.
 */

import {
  RegisterDocumentTypeInputSchema,
  PublishDocumentTypeDefinitionInputSchema,
  InitiateFileUploadInputSchema,
  RecordFileScanResultInputSchema,
  AuthorizeFileAccessInputSchema,
  CreateFileVersionInputSchema,
  RequestFileDeletionInputSchema,
  SetFileLegalHoldInputSchema,
  ConfigVersionSchema,
  parseDocumentType,
  parseFile,
  parseFileAccessLog,
  type RegisterDocumentTypeInput,
  type PublishDocumentTypeDefinitionInput,
  type InitiateFileUploadInput,
  type RecordFileScanResultInput,
  type AuthorizeFileAccessInput,
  type CreateFileVersionInput,
  type RequestFileDeletionInput,
  type SetFileLegalHoldInput,
  type DocumentType,
  type File,
  type FileAccessLog,
  type ConfigVersion,
} from "../contracts/document/document.ts";
import { parseConfigVersion } from "../contracts/config/config.ts";

export interface DocumentMutationRpcClient {
  rpc(
    fn:
      | "register_document_type"
      | "publish_document_type_definition"
      | "initiate_file_upload"
      | "record_file_scan_result"
      | "authorize_file_access"
      | "create_file_version"
      | "request_file_deletion"
      | "set_file_legal_hold",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const DOCUMENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "file_actor_unauthorized",
  "document_missing_mime_types",
  "document_invalid_mime_type",
  "document_missing_max_size",
  "document_invalid_max_size",
  "document_invalid_retention_class",
  "document_invalid_default_classification",
  "document_missing_legal_hold_eligible",
  "document_type_not_configured",
  "document_unsafe_filename",
  "document_mime_type_not_allowed",
  "document_file_too_large",
  "document_invalid_classification",
  "document_classification_too_weak",
  "document_type_not_legal_hold_eligible",
  "document_legal_hold_reason_required",
  "document_file_not_found",
  "document_scan_status_invalid",
  "document_scan_already_resolved",
  "document_access_type_invalid",
  "document_version_unauthorized",
  "document_version_of_deleted_file",
  "document_version_not_latest",
  "document_deletion_unauthorized",
  "document_legal_hold_blocks_deletion",
  "document_legal_hold_unauthorized",
] as const;
type KnownDocumentMutationErrorCode = (typeof DOCUMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type DocumentMutationErrorCode = KnownDocumentMutationErrorCode | "mutation_failed" | "invalid_response";

export class DocumentMutationError extends Error {
  readonly code: DocumentMutationErrorCode;

  constructor(code: DocumentMutationErrorCode, message: string) {
    super(message);
    this.name = "DocumentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): DocumentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (DOCUMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownDocumentMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent -- Supreme-Admin-only. Also mints a dedicated document:<code> config_type. */
export async function registerDocumentType(client: DocumentMutationRpcClient, input: RegisterDocumentTypeInput): Promise<DocumentType> {
  const parsedInput = RegisterDocumentTypeInputSchema.parse(input);
  const { data, error } = await client.rpc("register_document_type", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_owner_primitive_code: parsedInput.ownerPrimitiveCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "register_document_type returned no row");
  }
  return parseDocumentType(data as Record<string, unknown>);
}

/** Runs the structural validation gate (bounded MIME allowlist, bounded size ceiling, real retention/classification enums), then supersedes the prior published definition. */
export async function publishDocumentTypeDefinition(client: DocumentMutationRpcClient, input: PublishDocumentTypeDefinitionInput): Promise<ConfigVersion> {
  const parsedInput = PublishDocumentTypeDefinitionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_document_type_definition", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "publish_document_type_definition returned no row");
  }
  return ConfigVersionSchema.parse(parseConfigVersion(data as Record<string, unknown>));
}

/** Creates the file metadata row and a real, unguessable, server-generated storage_path -- content bytes are never stored here (disclosed NOT_RUN, no live storage provider in this sandbox). Idempotent on (tenant, idempotencyKey). */
export async function initiateFileUpload(client: DocumentMutationRpcClient, input: InitiateFileUploadInput): Promise<File> {
  const parsedInput = InitiateFileUploadInputSchema.parse(input);
  const { data, error } = await client.rpc("initiate_file_upload", {
    p_tenant_id: parsedInput.tenantId,
    p_document_type_code: parsedInput.documentTypeCode,
    p_record_type: parsedInput.recordType,
    p_record_id: parsedInput.recordId,
    p_original_filename: parsedInput.originalFilename,
    p_mime_type: parsedInput.mimeType,
    p_size_bytes: parsedInput.sizeBytes,
    p_classification: parsedInput.classification,
    p_legal_hold: parsedInput.legalHold,
    p_legal_hold_reason: parsedInput.legalHoldReason,
    p_shared_org_unit_ids: parsedInput.sharedOrgUnitIds,
    p_customer_account_ref: parsedInput.customerAccountRef,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "initiate_file_upload returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}

/** The bounded malware-scan adapter interface a real scan provider webhook/job calls to report one file's outcome -- this repository never calls it against a fabricated scanner itself. Idempotent-safe: re-resolving to the same status is a no-op. */
export async function recordFileScanResult(client: DocumentMutationRpcClient, input: RecordFileScanResultInput): Promise<File> {
  const parsedInput = RecordFileScanResultInputSchema.parse(input);
  const { data, error } = await client.rpc("record_file_scan_result", {
    p_file_id: parsedInput.fileId,
    p_status: parsedInput.status,
    p_provider_ref: parsedInput.providerRef,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "record_file_scan_result returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}

/** The single gate a real signed-URL-issuing server action calls before generating one -- composes the malware-scan gate and the record/sensitivity access gate, and always returns a logged evidence row for a legitimate-but-denied attempt (an actor with no tenant standing at all is refused outright instead, see DocumentMutationError code file_actor_unauthorized). */
export async function authorizeFileAccess(client: DocumentMutationRpcClient, input: AuthorizeFileAccessInput): Promise<FileAccessLog> {
  const parsedInput = AuthorizeFileAccessInputSchema.parse(input);
  const { data, error } = await client.rpc("authorize_file_access", {
    p_file_id: parsedInput.fileId,
    p_access_type: parsedInput.accessType,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_correlation_id: parsedInput.correlationId,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "authorize_file_access returned no row");
  }
  return parseFileAccessLog(data as Record<string, unknown>);
}

/** Always inserts a new row -- never overwrites. Only the original uploader or a support/Supreme authority may add a new version, and only from the current latest version of a not-yet-deleted file. */
export async function createFileVersion(client: DocumentMutationRpcClient, input: CreateFileVersionInput): Promise<File> {
  const parsedInput = CreateFileVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_file_version", {
    p_previous_file_id: parsedInput.previousFileId,
    p_original_filename: parsedInput.originalFilename,
    p_mime_type: parsedInput.mimeType,
    p_size_bytes: parsedInput.sizeBytes,
    p_classification: parsedInput.classification,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "create_file_version returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}

/** Soft delete only (deleted_at, never physical). Idempotent. Refuses outright while legal_hold is true. */
export async function requestFileDeletion(client: DocumentMutationRpcClient, input: RequestFileDeletionInput): Promise<File> {
  const parsedInput = RequestFileDeletionInputSchema.parse(input);
  const { data, error } = await client.rpc("request_file_deletion", {
    p_file_id: parsedInput.fileId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "request_file_deletion returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}

/** A privileged action -- support/Supreme authority only, not any active tenant member. */
export async function setFileLegalHold(client: DocumentMutationRpcClient, input: SetFileLegalHoldInput): Promise<File> {
  const parsedInput = SetFileLegalHoldInputSchema.parse(input);
  const { data, error } = await client.rpc("set_file_legal_hold", {
    p_file_id: parsedInput.fileId,
    p_legal_hold: parsedInput.legalHold,
    p_legal_hold_reason: parsedInput.legalHoldReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new DocumentMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new DocumentMutationError("invalid_response", "set_file_legal_hold returned no row");
  }
  return parseFile(data as Record<string, unknown>);
}
