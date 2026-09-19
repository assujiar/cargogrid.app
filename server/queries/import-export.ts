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
  parseImportStagingRow,
  parseImportExportJob,
  type ResolveImportExportSchemaColumnsInput,
  type PreviewImportJobInput,
  type ResolvedImportExportSchemaColumns,
  type ImportJobPreview,
  type ImportStagingRow,
  type ImportExportJob,
} from "../contracts/import-export/import-export.ts";

export interface ImportExportQueryRpcClient {
  rpc(
    fn: "resolve_import_export_schema_columns" | "preview_import_job" | "sanitize_formula_injection" | "list_import_staging_rows" | "get_import_export_job",
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

/** CG-AUDIT-2026-09-02 A4: the one full-row read for a job reachable through PostgREST -- app.jobs' own direct-table RLS for authenticated is real but unreachable from the JS client surface (app is not exposed to PostgREST, and no public.jobs view exists). Same authority gate as previewImportJob/listImportStagingRows. */
export async function getImportExportJob(client: ImportExportQueryRpcClient, input: { jobId: string; actorAuthUserId: string }): Promise<ImportExportJob> {
  const { data, error } = await client.rpc("get_import_export_job", {
    p_job_id: input.jobId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ImportExportQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ImportExportQueryError("get_import_export_job returned no row");
  }
  return parseImportExportJob(row);
}

/** CG-AUDIT-2026-09-02 A4: the row-level sibling of previewImportJob -- same authority gate (job requester or tenant support/Supreme authority), returning every staged row (raw_payload/validation_status/error) for one job so a reviewer can see exactly which rows failed and why before committing. */
export async function listImportStagingRows(client: ImportExportQueryRpcClient, input: { jobId: string; actorAuthUserId: string }): Promise<ImportStagingRow[]> {
  const { data, error } = await client.rpc("list_import_staging_rows", {
    p_job_id: input.jobId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ImportExportQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseImportStagingRow(row as Record<string, unknown>));
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
