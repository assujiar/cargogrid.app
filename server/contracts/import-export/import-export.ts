/**
 * Import/export job framework contract (PLT-131, CG-S6-PLT-028). Mirrors
 * supabase/migrations/20260719170000_create_import_export_job_framework.sql's
 * app.import_export_schemas/app.jobs/app.import_staging_rows shape and the
 * app.register_import_export_schema / app.publish_import_export_schema /
 * app.resolve_import_export_schema_columns / app.create_import_export_job /
 * app.stage_import_rows / app.validate_staging_row / app.preview_import_job /
 * app.commit_import_job / app.cancel_import_export_job /
 * app.acknowledge_job_cancellation / app.complete_export_job /
 * app.record_job_failure / app.requeue_dead_letter_job /
 * app.sanitize_formula_injection RPCs.
 *
 * job_type is deliberately narrowed to ('import','export') here, matching the
 * migration's own disclosed scope boundary -- Prompt 132 (Background Job Framework)
 * will widen app.jobs' own CHECK constraint (and this contract) in its own migration.
 */

import { z } from "zod";
import { ConfigVersionSchema, type ConfigVersion } from "../config/config.ts";

export const IMPORT_EXPORT_JOB_TYPES = ["import", "export"] as const;
export const ImportExportJobTypeSchema = z.enum(IMPORT_EXPORT_JOB_TYPES);
export type ImportExportJobType = z.infer<typeof ImportExportJobTypeSchema>;

export const IMPORT_EXPORT_JOB_STATUSES = [
  "pending",
  "in_progress",
  "cancelling",
  "cancelled",
  "completed",
  "failed",
  "dead_letter",
] as const;
export const ImportExportJobStatusSchema = z.enum(IMPORT_EXPORT_JOB_STATUSES);
export type ImportExportJobStatus = z.infer<typeof ImportExportJobStatusSchema>;

export const IMPORT_EXPORT_ROW_VALIDATION_STATUSES = ["pending", "valid", "invalid"] as const;
export const ImportExportRowValidationStatusSchema = z.enum(IMPORT_EXPORT_ROW_VALIDATION_STATUSES);
export type ImportExportRowValidationStatus = z.infer<typeof ImportExportRowValidationStatusSchema>;

export const IMPORT_EXPORT_COLUMN_DATA_TYPES = ["text", "number", "boolean", "date", "email"] as const;
export const ImportExportColumnDataTypeSchema = z.enum(IMPORT_EXPORT_COLUMN_DATA_TYPES);
export type ImportExportColumnDataType = z.infer<typeof ImportExportColumnDataTypeSchema>;

export const ImportExportColumnDefinitionSchema = z.object({
  key: z.string().min(1),
  label: z.string().min(1),
  required: z.boolean(),
  data_type: ImportExportColumnDataTypeSchema,
});
export type ImportExportColumnDefinition = z.infer<typeof ImportExportColumnDefinitionSchema>;

export const ImportExportSchemaSchema = z.object({
  code: z.string(),
  name: z.string(),
  ownerPrimitiveCode: z.string(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ImportExportSchema = z.infer<typeof ImportExportSchemaSchema>;

export const ResolvedImportExportSchemaColumnsSchema = z.object({
  configVersionId: z.string().uuid(),
  columns: z.array(ImportExportColumnDefinitionSchema),
});
export type ResolvedImportExportSchemaColumns = z.infer<typeof ResolvedImportExportSchemaColumnsSchema>;

export const ImportExportJobSchema = z.object({
  jobId: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobType: ImportExportJobTypeSchema,
  status: ImportExportJobStatusSchema,
  priority: z.number().int(),
  payload: z.record(z.string(), z.unknown()),
  attempts: z.number().int().nonnegative(),
  maxAttempts: z.number().int().positive(),
  lockedBy: z.string().nullable(),
  lockedUntil: z.string().nullable(),
  error: z.string().nullable(),
  resultUrl: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid(),
  idempotencyKey: z.string().nullable(),
  importExportSchemaCode: z.string().nullable(),
  sourceFileId: z.string().uuid().nullable(),
  resultFileId: z.string().uuid().nullable(),
  totalRows: z.number().int().nonnegative().nullable(),
  processedRows: z.number().int().nonnegative(),
  validRowCount: z.number().int().nonnegative(),
  invalidRowCount: z.number().int().nonnegative(),
  cancelReason: z.string().nullable(),
  updatedAt: z.string(),
});
export type ImportExportJob = z.infer<typeof ImportExportJobSchema>;

export const ImportStagingRowSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobId: z.string().uuid(),
  rowNumber: z.number().int().positive(),
  rawPayload: z.record(z.string(), z.unknown()),
  validationStatus: ImportExportRowValidationStatusSchema,
  error: z.string().nullable(),
  createdAt: z.string(),
});
export type ImportStagingRow = z.infer<typeof ImportStagingRowSchema>;

export const ImportJobPreviewSchema = z.object({
  totalRows: z.number().int().nonnegative(),
  validRows: z.number().int().nonnegative(),
  invalidRows: z.number().int().nonnegative(),
  pendingRows: z.number().int().nonnegative(),
});
export type ImportJobPreview = z.infer<typeof ImportJobPreviewSchema>;

export const RegisterImportExportSchemaInputSchema = z.object({
  code: z.string().min(1),
  name: z.string().min(1),
  ownerPrimitiveCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  registeredBy: z.string().min(1),
});
export type RegisterImportExportSchemaInput = z.input<typeof RegisterImportExportSchemaInputSchema>;

export const PublishImportExportSchemaInputSchema = z.object({
  versionId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  effectiveFrom: z.string(),
  actorLabel: z.string().min(1),
});
export type PublishImportExportSchemaInput = z.input<typeof PublishImportExportSchemaInputSchema>;

export const ResolveImportExportSchemaColumnsInputSchema = z.object({
  tenantId: z.string().uuid(),
  schemaCode: z.string().min(1),
});
export type ResolveImportExportSchemaColumnsInput = z.input<typeof ResolveImportExportSchemaColumnsInputSchema>;

export const CreateImportExportJobInputSchema = z.object({
  tenantId: z.string().uuid(),
  jobType: ImportExportJobTypeSchema,
  schemaCode: z.string().min(1),
  sourceFileId: z.string().uuid().nullable().default(null),
  filters: z.record(z.string(), z.unknown()).default({}),
  idempotencyKey: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateImportExportJobInput = z.input<typeof CreateImportExportJobInputSchema>;

export const StageImportRowsInputSchema = z.object({
  jobId: z.string().uuid(),
  rows: z.array(z.record(z.string(), z.unknown())).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type StageImportRowsInput = z.input<typeof StageImportRowsInputSchema>;

export const ValidateStagingRowInputSchema = z.object({
  stagingRowId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ValidateStagingRowInput = z.input<typeof ValidateStagingRowInputSchema>;

export const PreviewImportJobInputSchema = z.object({
  jobId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type PreviewImportJobInput = z.input<typeof PreviewImportJobInputSchema>;

export const CommitImportJobInputSchema = z.object({
  jobId: z.string().uuid(),
  allowPartial: z.boolean().default(false),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CommitImportJobInput = z.input<typeof CommitImportJobInputSchema>;

export const CancelImportExportJobInputSchema = z.object({
  jobId: z.string().uuid(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelImportExportJobInput = z.input<typeof CancelImportExportJobInputSchema>;

export const AcknowledgeJobCancellationInputSchema = z.object({
  jobId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AcknowledgeJobCancellationInput = z.input<typeof AcknowledgeJobCancellationInputSchema>;

export const CompleteExportJobInputSchema = z.object({
  jobId: z.string().uuid(),
  resultFileId: z.string().uuid(),
  rowCount: z.number().int().nonnegative(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CompleteExportJobInput = z.input<typeof CompleteExportJobInputSchema>;

export const RecordJobFailureInputSchema = z.object({
  jobId: z.string().uuid(),
  errorMessage: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordJobFailureInput = z.input<typeof RecordJobFailureInputSchema>;

export const RequeueDeadLetterJobInputSchema = z.object({
  jobId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequeueDeadLetterJobInput = z.input<typeof RequeueDeadLetterJobInputSchema>;

export function parseImportExportSchema(row: Record<string, unknown>): ImportExportSchema {
  return ImportExportSchemaSchema.parse({
    code: row.code,
    name: row.name,
    ownerPrimitiveCode: row.owner_primitive_code,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Reuses app.config_versions' own shape (PLT-121) -- publish_import_export_schema wraps app.publish_config_version directly. */
export function parseImportExportSchemaVersion(row: Record<string, unknown>): ConfigVersion {
  return ConfigVersionSchema.parse({
    id: row.id,
    configObjectId: row.config_object_id,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    clonedFromVersionId: row.cloned_from_version_id,
    rollbackOfVersionId: row.rollback_of_version_id,
    createdBy: row.created_by,
    publishedBy: row.published_by,
    publishedAt: row.published_at,
    archivedAt: row.archived_at,
    archivedReason: row.archived_reason,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export function parseResolvedImportExportSchemaColumns(row: Record<string, unknown>): ResolvedImportExportSchemaColumns {
  return ResolvedImportExportSchemaColumnsSchema.parse({
    configVersionId: row.config_version_id,
    columns: row.columns,
  });
}

export function parseImportExportJob(row: Record<string, unknown>): ImportExportJob {
  return ImportExportJobSchema.parse({
    jobId: row.job_id,
    tenantId: row.tenant_id,
    jobType: row.job_type,
    status: row.status,
    priority: row.priority,
    payload: row.payload,
    attempts: row.attempts,
    maxAttempts: row.max_attempts,
    lockedBy: row.locked_by,
    lockedUntil: row.locked_until,
    error: row.error,
    resultUrl: row.result_url,
    createdBy: row.created_by,
    createdAt: row.created_at,
    completedAt: row.completed_at,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    idempotencyKey: row.idempotency_key,
    importExportSchemaCode: row.import_export_schema_code,
    sourceFileId: row.source_file_id,
    resultFileId: row.result_file_id,
    totalRows: row.total_rows,
    processedRows: row.processed_rows,
    validRowCount: row.valid_row_count,
    invalidRowCount: row.invalid_row_count,
    cancelReason: row.cancel_reason,
    updatedAt: row.updated_at,
  });
}

export function parseImportStagingRow(row: Record<string, unknown>): ImportStagingRow {
  return ImportStagingRowSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobId: row.job_id,
    rowNumber: row.row_number,
    rawPayload: row.raw_payload,
    validationStatus: row.validation_status,
    error: row.error,
    createdAt: row.created_at,
  });
}

export function parseImportJobPreview(row: Record<string, unknown>): ImportJobPreview {
  return ImportJobPreviewSchema.parse({
    totalRows: row.total_rows,
    validRows: row.valid_rows,
    invalidRows: row.invalid_rows,
    pendingRows: row.pending_rows,
  });
}
