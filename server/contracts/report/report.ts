/**
 * Commercial Reports contract (COM-159, CG-S7-COM-018), extended by IAE-002
 * (Reporting Engine, Prompt 330). Mirrors
 * supabase/migrations/20260724330000_create_commercial_reports.sql's
 * app.report_types/app.report_runs shape and
 * supabase/migrations/20260802010000_create_intelligence_reporting_engine.sql's
 * app.report_type_versions, parameter_schema and cancel_report_run additions.
 */

import { z } from "zod";

export const REPORT_TYPE_STATUSES = ["active", "retired"] as const;
export const ReportTypeStatusSchema = z.enum(REPORT_TYPE_STATUSES);
export type ReportTypeStatus = z.infer<typeof ReportTypeStatusSchema>;

export const REPORT_RUN_TYPES = ["preview", "export"] as const;
export const ReportRunTypeSchema = z.enum(REPORT_RUN_TYPES);
export type ReportRunType = z.infer<typeof ReportRunTypeSchema>;

export const REPORT_RUN_STATUSES = ["queued", "running", "completed", "failed"] as const;
export const ReportRunStatusSchema = z.enum(REPORT_RUN_STATUSES);
export type ReportRunStatus = z.infer<typeof ReportRunStatusSchema>;

/** IAE-002: structural per-report parameter contract, e.g. {"currency": {"type": "string", "required": false}}. Empty object (every pre-existing report) means no engine-level contract -- app.validate_report_parameters defers entirely to the domain source_function. */
export const ReportParameterFieldSchema = z.object({
  type: z.enum(["string", "number", "boolean", "object", "array"]).optional(),
  required: z.boolean().optional(),
});
export const ReportParameterSchemaSchema = z.record(z.string(), ReportParameterFieldSchema);
export type ReportParameterSchema = z.infer<typeof ReportParameterSchemaSchema>;

export const ReportTypeSchema = z.object({
  code: z.string(),
  name: z.string(),
  description: z.string(),
  sourceFunction: z.string(),
  parameterSchema: ReportParameterSchemaSchema,
  version: z.number().int().positive(),
  status: ReportTypeStatusSchema,
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ReportType = z.infer<typeof ReportTypeSchema>;

export function parseReportType(row: Record<string, unknown>): ReportType {
  return ReportTypeSchema.parse({
    code: row.code,
    name: row.name,
    description: row.description,
    sourceFunction: row.source_function,
    parameterSchema: row.parameter_schema ?? {},
    version: row.version,
    status: row.status,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** IAE-002: one immutable, append-only definition-version history row. app.report_types itself always reflects the latest published version -- a report_runs row cites the exact version it ran against via reportTypeVersionId, never rewritten by a later publish. */
export const ReportTypeVersionSchema = z.object({
  id: z.string().uuid(),
  reportTypeCode: z.string(),
  versionNumber: z.number().int().positive(),
  sourceFunction: z.string(),
  parameterSchema: ReportParameterSchemaSchema,
  description: z.string(),
  publishedByAuthUserId: z.string().uuid().nullable(),
  publishedBy: z.string().nullable(),
  publishedAt: z.string(),
});
export type ReportTypeVersion = z.infer<typeof ReportTypeVersionSchema>;

export function parseReportTypeVersion(row: Record<string, unknown>): ReportTypeVersion {
  return ReportTypeVersionSchema.parse({
    id: row.id,
    reportTypeCode: row.report_type_code,
    versionNumber: row.version_number,
    sourceFunction: row.source_function,
    parameterSchema: row.parameter_schema ?? {},
    description: row.description,
    publishedByAuthUserId: row.published_by_auth_user_id,
    publishedBy: row.published_by,
    publishedAt: row.published_at,
  });
}

export const ReportRunSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  reportTypeCode: z.string(),
  runType: ReportRunTypeSchema,
  status: ReportRunStatusSchema,
  parameters: z.record(z.string(), z.unknown()),
  rowCount: z.coerce.number().int().nonnegative().nullable(),
  maskedColumns: z.array(z.string()),
  jobId: z.string().uuid().nullable(),
  fileId: z.string().uuid().nullable(),
  reportTypeVersionId: z.string().uuid().nullable(),
  errorReason: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid(),
  createdBy: z.string().nullable(),
  requestedAt: z.string(),
  completedAt: z.string().nullable(),
});
export type ReportRun = z.infer<typeof ReportRunSchema>;

export function parseReportRun(row: Record<string, unknown>): ReportRun {
  return ReportRunSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    reportTypeCode: row.report_type_code,
    runType: row.run_type,
    status: row.status,
    parameters: row.parameters,
    rowCount: row.row_count,
    maskedColumns: row.masked_columns,
    jobId: row.job_id,
    fileId: row.file_id,
    reportTypeVersionId: row.report_type_version_id ?? null,
    errorReason: row.error_reason,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    createdBy: row.created_by,
    requestedAt: row.requested_at,
    completedAt: row.completed_at,
  });
}

/**
 * IAE-002: a generic, flat parameter bag. Historically a fixed 4-field shape
 * (orgUnitId/ownerUserId/periodStart/periodEnd) mirroring the original 7
 * Commercial dashboard functions' own inputs -- widened to any flat record so
 * a report registered with a real app.report_types.parameterSchema (e.g.
 * {"currency": {...}}) can pass its own declared keys through unmodified.
 * The real authority is server-side (app.validate_report_parameters); this
 * schema only bounds the value shape to safe, flat, non-recursive primitives.
 */
export const ReportParametersSchema = z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()]));
export type ReportParameters = z.input<typeof ReportParametersSchema>;

export const RecordReportRunInputSchema = z.object({
  tenantId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  parameters: ReportParametersSchema.default({}),
  rowCount: z.number().int().nonnegative(),
  maskedColumns: z.array(z.string()).default([]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordReportRunInput = z.input<typeof RecordReportRunInputSchema>;

export const EnqueueReportExportInputSchema = z.object({
  tenantId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  parameters: ReportParametersSchema.default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EnqueueReportExportInput = z.input<typeof EnqueueReportExportInputSchema>;

/** IAE-002: Supreme-only. Publishes a new report-type definition version -- app.report_types moves to this new "current" state, and the immutable version history gains one new row. */
export const PublishReportTypeVersionInputSchema = z.object({
  code: z.string().min(1),
  sourceFunction: z.string().min(1),
  parameterSchema: ReportParameterSchemaSchema,
  description: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PublishReportTypeVersionInput = z.input<typeof PublishReportTypeVersionInputSchema>;

/** IAE-002: cancels a still-queued export run. The original requester, an actor holding COM:Export, or Supreme Admin may cancel. */
export const CancelReportRunInputSchema = z.object({
  runId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelReportRunInput = z.input<typeof CancelReportRunInputSchema>;
