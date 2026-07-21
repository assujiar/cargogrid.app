/**
 * Document and file engine contract (PLT-128, CG-S6-PLT-025). Mirrors
 * supabase/migrations/20260719140000_create_document_file_engine.sql's
 * app.document_types/app.files/app.file_access_logs shape and the
 * app.register_document_type / app.publish_document_type_definition /
 * app.initiate_file_upload / app.record_file_scan_result /
 * app.authorize_file_access / app.create_file_version /
 * app.request_file_deletion / app.set_file_legal_hold RPCs.
 *
 * A document *type definition* (allowed MIME types, max size, retention class, default
 * classification, legal-hold eligibility) is not modeled here as its own row type -- it
 * is PLT-121's own ConfigVersion/config_items (config_type_code='document:<code>'),
 * reused directly (the migration's own header). `publishDocumentTypeDefinition`
 * therefore still returns a `ConfigVersion` (server/contracts/config/config.ts).
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const SENSITIVITY_LEVELS = ["public", "internal", "confidential", "restricted", "credential"] as const;
export const ClassificationSchema = z.enum(SENSITIVITY_LEVELS);
export type Classification = z.infer<typeof ClassificationSchema>;

export const MALWARE_SCAN_STATUSES = ["pending", "clean", "infected", "error"] as const;
export const MalwareScanStatusSchema = z.enum(MALWARE_SCAN_STATUSES);
export type MalwareScanStatus = z.infer<typeof MalwareScanStatusSchema>;

export const FILE_LIFECYCLE_STATUSES = ["active", "superseded", "deleted"] as const;
export const FileLifecycleStatusSchema = z.enum(FILE_LIFECYCLE_STATUSES);
export type FileLifecycleStatus = z.infer<typeof FileLifecycleStatusSchema>;

export const FILE_ACCESS_TYPES = ["signed_url_issued", "download", "metadata_view"] as const;
export const FileAccessTypeSchema = z.enum(FILE_ACCESS_TYPES);
export type FileAccessType = z.infer<typeof FileAccessTypeSchema>;

export const FILE_ACCESS_RESULTS = ["granted", "denied"] as const;
export const FileAccessResultSchema = z.enum(FILE_ACCESS_RESULTS);
export type FileAccessResult = z.infer<typeof FileAccessResultSchema>;

export const DocumentTypeSchema = z.object({
  code: z.string(),
  name: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type DocumentType = z.infer<typeof DocumentTypeSchema>;

export const FileSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  documentTypeCode: z.string(),
  configVersionId: z.string().uuid(),
  recordType: z.string(),
  recordId: z.string().uuid(),
  classification: ClassificationSchema,
  originalFilename: z.string(),
  mimeType: z.string(),
  sizeBytes: z.number().int().positive(),
  storagePath: z.string(),
  malwareScanStatus: MalwareScanStatusSchema,
  malwareScanCompletedAt: z.string().nullable(),
  malwareScanProviderRef: z.string().nullable(),
  versionGroupId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isLatestVersion: z.boolean(),
  lifecycleStatus: FileLifecycleStatusSchema,
  legalHold: z.boolean(),
  legalHoldReason: z.string().nullable(),
  deletedAt: z.string().nullable(),
  uploadedByAuthUserId: z.string().uuid(),
  sharedOrgUnitIds: z.array(z.string().uuid()),
  customerAccountRef: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type File = z.infer<typeof FileSchema>;

export const FileAccessLogSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  fileId: z.string().uuid(),
  accessedByAuthUserId: z.string().uuid(),
  accessType: FileAccessTypeSchema,
  result: FileAccessResultSchema,
  reason: z.string().nullable(),
  correlationId: z.string().uuid().nullable(),
  accessedAt: z.string(),
});
export type FileAccessLog = z.infer<typeof FileAccessLogSchema>;

export const RegisterDocumentTypeInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  ownerPrimitiveCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterDocumentTypeInput = z.input<typeof RegisterDocumentTypeInputSchema>;

export const PublishDocumentTypeDefinitionInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string().nullable().default(null),
  actorLabel: z.string().min(1),
});
export type PublishDocumentTypeDefinitionInput = z.input<typeof PublishDocumentTypeDefinitionInputSchema>;

export const InitiateFileUploadInputSchema = z.object({
  tenantId: z.string().uuid(),
  documentTypeCode: z.string().min(1),
  recordType: z.string().min(1),
  recordId: z.string().uuid(),
  originalFilename: z.string().min(1),
  mimeType: z.string().min(1),
  sizeBytes: z.number().int().positive(),
  classification: ClassificationSchema.nullable().default(null),
  legalHold: z.boolean().default(false),
  legalHoldReason: z.string().nullable().default(null),
  sharedOrgUnitIds: z.array(z.string().uuid()).default([]),
  customerAccountRef: z.string().nullable().default(null),
  idempotencyKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type InitiateFileUploadInput = z.input<typeof InitiateFileUploadInputSchema>;

export const RecordFileScanResultInputSchema = z.object({
  fileId: z.string().uuid(),
  status: z.enum(["clean", "infected", "error"]),
  providerRef: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordFileScanResultInput = z.input<typeof RecordFileScanResultInputSchema>;

export const AuthorizeFileAccessInputSchema = z.object({
  fileId: z.string().uuid(),
  accessType: FileAccessTypeSchema,
  actorAuthUserId: z.string().uuid(),
  correlationId: z.string().uuid().nullable().default(null),
});
export type AuthorizeFileAccessInput = z.input<typeof AuthorizeFileAccessInputSchema>;

export const CreateFileVersionInputSchema = z.object({
  previousFileId: z.string().uuid(),
  originalFilename: z.string().min(1),
  mimeType: z.string().min(1),
  sizeBytes: z.number().int().positive(),
  classification: ClassificationSchema.nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateFileVersionInput = z.input<typeof CreateFileVersionInputSchema>;

export const RequestFileDeletionInputSchema = z.object({
  fileId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestFileDeletionInput = z.input<typeof RequestFileDeletionInputSchema>;

export const SetFileLegalHoldInputSchema = z.object({
  fileId: z.string().uuid(),
  legalHold: z.boolean(),
  legalHoldReason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetFileLegalHoldInput = z.input<typeof SetFileLegalHoldInputSchema>;

/** Re-exported so callers of publishDocumentTypeDefinition don't need a separate import from ../config/config.ts. */
export { ConfigVersionSchema };
export type { ConfigVersion };

/** Maps a raw app.document_types row (snake_case) to this contract's camelCase shape. */
export function parseDocumentType(row: Record<string, unknown>): DocumentType {
  return DocumentTypeSchema.parse({
    code: row.code,
    name: row.name,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Maps a raw app.files row (snake_case) to this contract's camelCase shape. */
export function parseFile(row: Record<string, unknown>): File {
  return FileSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    documentTypeCode: row.document_type_code,
    configVersionId: row.config_version_id,
    recordType: row.record_type,
    recordId: row.record_id,
    classification: row.classification,
    originalFilename: row.original_filename,
    mimeType: row.mime_type,
    sizeBytes: row.size_bytes,
    storagePath: row.storage_path,
    malwareScanStatus: row.malware_scan_status,
    malwareScanCompletedAt: row.malware_scan_completed_at,
    malwareScanProviderRef: row.malware_scan_provider_ref,
    versionGroupId: row.version_group_id,
    versionNumber: row.version_number,
    isLatestVersion: row.is_latest_version,
    lifecycleStatus: row.lifecycle_status,
    legalHold: row.legal_hold,
    legalHoldReason: row.legal_hold_reason,
    deletedAt: row.deleted_at,
    uploadedByAuthUserId: row.uploaded_by_auth_user_id,
    sharedOrgUnitIds: row.shared_org_unit_ids,
    customerAccountRef: row.customer_account_ref,
    idempotencyKey: row.idempotency_key,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.file_access_logs row (snake_case) to this contract's camelCase shape. */
export function parseFileAccessLog(row: Record<string, unknown>): FileAccessLog {
  return FileAccessLogSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    fileId: row.file_id,
    accessedByAuthUserId: row.accessed_by_auth_user_id,
    accessType: row.access_type,
    result: row.result,
    reason: row.reason,
    correlationId: row.correlation_id,
    accessedAt: row.accessed_at,
  });
}
