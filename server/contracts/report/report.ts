/**
 * Commercial Reports contract (COM-159, CG-S7-COM-018). Mirrors
 * supabase/migrations/20260724330000_create_commercial_reports.sql's
 * app.report_types/app.report_runs shape and their RPCs.
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

export const ReportTypeSchema = z.object({
  code: z.string(),
  name: z.string(),
  description: z.string(),
  sourceFunction: z.string(),
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
    version: row.version,
    status: row.status,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
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
    errorReason: row.error_reason,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    createdBy: row.created_by,
    requestedAt: row.requested_at,
    completedAt: row.completed_at,
  });
}

/** The same filter shape server/contracts/dashboard/dashboard.ts's DashboardScopeFilterSchema uses -- every report's parameters mirror its underlying app.get_dashboard_* function's own inputs. */
export const ReportParametersSchema = z.object({
  orgUnitId: z.string().uuid().nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
  periodStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().default(null),
  periodEnd: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().default(null),
});
export type ReportParameters = z.input<typeof ReportParametersSchema>;

export const RecordReportRunInputSchema = z.object({
  tenantId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  parameters: ReportParametersSchema.default({ orgUnitId: null, ownerUserId: null, periodStart: null, periodEnd: null }),
  rowCount: z.number().int().nonnegative(),
  maskedColumns: z.array(z.string()).default([]),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordReportRunInput = z.input<typeof RecordReportRunInputSchema>;

export const EnqueueReportExportInputSchema = z.object({
  tenantId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  parameters: ReportParametersSchema.default({ orgUnitId: null, ownerUserId: null, periodStart: null, periodEnd: null }),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type EnqueueReportExportInput = z.input<typeof EnqueueReportExportInputSchema>;
