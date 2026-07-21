/**
 * Import/export job framework read queries (PLT-131, CG-S6-PLT-028). Thin, typed
 * wrappers around app.resolve_import_export_schema_columns / app.preview_import_job /
 * app.sanitize_formula_injection
 * (supabase/migrations/20260719170000_create_import_export_job_framework.sql).
 * app.preview_import_job is the one `authenticated`-callable function (SECURITY DEFINER,
 * requester-or-admin-authority-gated); the remaining two are service_role-only, matching
 * the migration's own server-mediated design.
 */

import {
  ResolveImportExportSchemaColumnsInputSchema,
  PreviewImportJobInputSchema,
  parseResolvedImportExportSchemaColumns,
  parseImportJobPreview,
  type ResolveImportExportSchemaColumnsInput,
  type PreviewImportJobInput,
  type ResolvedImportExportSchemaColumns,
  type ImportJobPreview,
} from "../contracts/import-export/import-export.ts";

export interface ImportExportQueryRpcClient {
  rpc(
    fn: "resolve_import_export_schema_columns" | "preview_import_job" | "sanitize_formula_injection",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ImportExportQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ImportExportQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Raises import_export_schema_not_configured if the tenant has never published a definition -- never fabricates a default column set. */
export async function resolveImportExportSchemaColumns(client: ImportExportQueryRpcClient, input: ResolveImportExportSchemaColumnsInput): Promise<ResolvedImportExportSchemaColumns> {
  const parsedInput = ResolveImportExportSchemaColumnsInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_import_export_schema_columns", {
    p_tenant_id: parsedInput.tenantId,
    p_schema_code: parsedInput.schemaCode,
  });
  if (error) {
    throw new ImportExportQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ImportExportQueryError("resolve_import_export_schema_columns returned no row");
  }
  return parseResolvedImportExportSchemaColumns(row);
}

/** Authority-gated to the job's own requester or their tenant's support/Supreme authority. */
export async function previewImportJob(client: ImportExportQueryRpcClient, input: PreviewImportJobInput): Promise<ImportJobPreview> {
  const parsedInput = PreviewImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("preview_import_job", {
    p_job_id: parsedInput.jobId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new ImportExportQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ImportExportQueryError("preview_import_job returned no row");
  }
  return parseImportJobPreview(row);
}

/** OWASP-recommended CSV/formula-injection mitigation -- pure computation, a future export-file writer calls this per output cell. Deliberately accepts the false-positive on legitimate leading-sign text (e.g. "-5"). */
export async function sanitizeFormulaInjection(client: ImportExportQueryRpcClient, value: string): Promise<string> {
  const { data, error } = await client.rpc("sanitize_formula_injection", { p_value: value });
  if (error) {
    throw new ImportExportQueryError(error.message);
  }
  if (typeof data !== "string") {
    throw new ImportExportQueryError("sanitize_formula_injection returned a non-string result");
  }
  return data;
}
