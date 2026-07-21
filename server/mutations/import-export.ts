/**
 * Import/export job framework mutation entry points (PLT-131, CG-S6-PLT-028). Thin,
 * typed wrappers around app.register_import_export_schema / app.publish_import_export_schema /
 * app.create_import_export_job / app.stage_import_rows / app.validate_staging_row /
 * app.commit_import_job / app.cancel_import_export_job / app.acknowledge_job_cancellation /
 * app.complete_export_job / app.record_job_failure / app.requeue_dead_letter_job
 * (supabase/migrations/20260719170000_create_import_export_job_framework.sql). Every one
 * of these is service_role-only (see the migration's own grant block and header) -- this
 * capability is server-mediated only, the same design PLT-128/129/130 established.
 */

import {
  RegisterImportExportSchemaInputSchema,
  PublishImportExportSchemaInputSchema,
  CreateImportExportJobInputSchema,
  StageImportRowsInputSchema,
  ValidateStagingRowInputSchema,
  CommitImportJobInputSchema,
  CancelImportExportJobInputSchema,
  AcknowledgeJobCancellationInputSchema,
  CompleteExportJobInputSchema,
  RecordJobFailureInputSchema,
  RequeueDeadLetterJobInputSchema,
  parseImportExportSchema,
  parseImportExportSchemaVersion,
  parseImportExportJob,
  parseImportStagingRow,
  type RegisterImportExportSchemaInput,
  type PublishImportExportSchemaInput,
  type CreateImportExportJobInput,
  type StageImportRowsInput,
  type ValidateStagingRowInput,
  type CommitImportJobInput,
  type CancelImportExportJobInput,
  type AcknowledgeJobCancellationInput,
  type CompleteExportJobInput,
  type RecordJobFailureInput,
  type RequeueDeadLetterJobInput,
  type ImportExportSchema,
  type ImportExportJob,
  type ImportStagingRow,
} from "../contracts/import-export/import-export.ts";
import type { ConfigVersion } from "../contracts/config/config.ts";

export interface ImportExportMutationRpcClient {
  rpc(
    fn:
      | "register_import_export_schema"
      | "publish_import_export_schema"
      | "create_import_export_job"
      | "stage_import_rows"
      | "validate_staging_row"
      | "commit_import_job"
      | "cancel_import_export_job"
      | "acknowledge_job_cancellation"
      | "complete_export_job"
      | "record_job_failure"
      | "requeue_dead_letter_job",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const IMPORT_EXPORT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "import_export_missing_columns",
  "import_export_invalid_column_key",
  "import_export_duplicate_column_key",
  "import_export_missing_column_label",
  "import_export_invalid_data_type",
  "import_export_missing_required_flag",
  "import_export_schema_not_configured",
  "job_actor_unauthorized",
  "import_export_invalid_job_type",
  "import_missing_source_file",
  "import_source_file_not_found",
  "export_unexpected_source_file",
  "import_export_unsafe_payload",
  "import_export_job_not_found",
  "import_export_wrong_job_type",
  "import_export_job_not_stageable",
  "import_source_file_infected",
  "import_source_file_not_yet_scanned",
  "import_export_missing_rows",
  "import_export_unsafe_row",
  "import_export_staging_row_not_found",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
  "import_export_job_already_terminal",
  "import_export_job_not_cancelling",
  "import_export_job_not_completable",
  "export_result_file_not_found",
  "job_requeue_unauthorized",
  "import_export_job_not_dead_letter",
] as const;
type KnownImportExportMutationErrorCode = (typeof IMPORT_EXPORT_KNOWN_MUTATION_ERROR_CODES)[number];
export type ImportExportMutationErrorCode = KnownImportExportMutationErrorCode | "mutation_failed" | "invalid_response";

export class ImportExportMutationError extends Error {
  readonly code: ImportExportMutationErrorCode;

  constructor(code: ImportExportMutationErrorCode, message: string) {
    super(message);
    this.name = "ImportExportMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ImportExportMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (IMPORT_EXPORT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownImportExportMutationErrorCode)
    : "mutation_failed";
}

/** Idempotent -- Supreme-Admin-only. Also mints an import_export:<code> config_type (PLT-121's registry reused, not forked). */
export async function registerImportExportSchema(client: ImportExportMutationRpcClient, input: RegisterImportExportSchemaInput): Promise<ImportExportSchema> {
  const parsedInput = RegisterImportExportSchemaInputSchema.parse(input);
  const { data, error } = await client.rpc("register_import_export_schema", {
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_owner_primitive_code: parsedInput.ownerPrimitiveCode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_registered_by: parsedInput.registeredBy,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "register_import_export_schema returned no row");
  }
  return parseImportExportSchema(data as Record<string, unknown>);
}

/** Wraps app.validate_import_export_schema_definition (structural gate) + app.publish_config_version (PLT-121 reused directly). */
export async function publishImportExportSchema(client: ImportExportMutationRpcClient, input: PublishImportExportSchemaInput): Promise<ConfigVersion> {
  const parsedInput = PublishImportExportSchemaInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_import_export_schema", {
    p_version_id: parsedInput.versionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_effective_from: parsedInput.effectiveFrom,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "publish_import_export_schema returned no row");
  }
  return parseImportExportSchemaVersion(data as Record<string, unknown>);
}

/** An import job requires a real, tenant-owned sourceFileId; an export job must not carry one. Idempotent per (tenant, idempotencyKey). */
export async function createImportExportJob(client: ImportExportMutationRpcClient, input: CreateImportExportJobInput): Promise<ImportExportJob> {
  const parsedInput = CreateImportExportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("create_import_export_job", {
    p_tenant_id: parsedInput.tenantId,
    p_job_type: parsedInput.jobType,
    p_schema_code: parsedInput.schemaCode,
    p_source_file_id: parsedInput.sourceFileId,
    p_filters: parsedInput.filters,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "create_import_export_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** Refuses to stage rows from a source file that is not yet clean (RPD-032, PLT-128 reused directly). Returns the job's new total staged row count. */
export async function stageImportRows(client: ImportExportMutationRpcClient, input: StageImportRowsInput): Promise<number> {
  const parsedInput = StageImportRowsInputSchema.parse(input);
  const { data, error } = await client.rpc("stage_import_rows", {
    p_job_id: parsedInput.jobId,
    p_rows: parsedInput.rows,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (typeof data !== "number") {
    throw new ImportExportMutationError("invalid_response", "stage_import_rows returned a non-numeric result");
  }
  return data;
}

/** Structural validation only (required-ness + per-data_type shape) -- never a domain write. Idempotent-safe: re-validating an already-resolved row adjusts the job's counters by the delta. */
export async function validateStagingRow(client: ImportExportMutationRpcClient, input: ValidateStagingRowInput): Promise<ImportStagingRow> {
  const parsedInput = ValidateStagingRowInputSchema.parse(input);
  const { data, error } = await client.rpc("validate_staging_row", {
    p_staging_row_id: parsedInput.stagingRowId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "validate_staging_row returned no row");
  }
  return parseImportStagingRow(data as Record<string, unknown>);
}

/** All-or-nothing by default: refuses while any row is pending validation, and refuses while any row is invalid unless allowPartial is set. */
export async function commitImportJob(client: ImportExportMutationRpcClient, input: CommitImportJobInput): Promise<ImportExportJob> {
  const parsedInput = CommitImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_import_job", {
    p_job_id: parsedInput.jobId,
    p_allow_partial: parsedInput.allowPartial,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "commit_import_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** Two-phase cooperative cancel: a pending job cancels immediately; an in_progress job moves to cancelling and requires acknowledgeJobCancellation to finish. */
export async function cancelImportExportJob(client: ImportExportMutationRpcClient, input: CancelImportExportJobInput): Promise<ImportExportJob> {
  const parsedInput = CancelImportExportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_import_export_job", {
    p_job_id: parsedInput.jobId,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "cancel_import_export_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** The real function a future worker calls the moment it notices the cancelling flag and stops cleanly -- only valid from status=cancelling. */
export async function acknowledgeJobCancellation(client: ImportExportMutationRpcClient, input: AcknowledgeJobCancellationInput): Promise<ImportExportJob> {
  const parsedInput = AcknowledgeJobCancellationInputSchema.parse(input);
  const { data, error } = await client.rpc("acknowledge_job_cancellation", {
    p_job_id: parsedInput.jobId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "acknowledge_job_cancellation returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** Attaches a real, tenant-owned result file (PLT-128) to a completed export job. */
export async function completeExportJob(client: ImportExportMutationRpcClient, input: CompleteExportJobInput): Promise<ImportExportJob> {
  const parsedInput = CompleteExportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("complete_export_job", {
    p_job_id: parsedInput.jobId,
    p_result_file_id: parsedInput.resultFileId,
    p_row_count: parsedInput.rowCount,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "complete_export_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** The bounded retry/DLQ adapter interface a real worker calls to report a failed attempt -- this repository never calls it against a fabricated live failure itself. Moves to dead_letter once attempts reach maxAttempts. */
export async function recordJobFailure(client: ImportExportMutationRpcClient, input: RecordJobFailureInput): Promise<ImportExportJob> {
  const parsedInput = RecordJobFailureInputSchema.parse(input);
  const { data, error } = await client.rpc("record_job_failure", {
    p_job_id: parsedInput.jobId,
    p_error_message: parsedInput.errorMessage,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "record_job_failure returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}

/** The manual replay step -- support/Supreme authority only, only valid from status=dead_letter. Resets attempts to 0. */
export async function requeueDeadLetterJob(client: ImportExportMutationRpcClient, input: RequeueDeadLetterJobInput): Promise<ImportExportJob> {
  const parsedInput = RequeueDeadLetterJobInputSchema.parse(input);
  const { data, error } = await client.rpc("requeue_dead_letter_job", {
    p_job_id: parsedInput.jobId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ImportExportMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ImportExportMutationError("invalid_response", "requeue_dead_letter_job returned no row");
  }
  return parseImportExportJob(data as Record<string, unknown>);
}
