/**
 * Scheduled Reports contract (IAE-006, Prompt 334). Mirrors
 * supabase/migrations/20260802050000_create_intelligence_scheduled_reports.sql's
 * app.scheduled_reports/app.scheduled_report_recipients/app.scheduled_report_runs
 * shape. cron_day_of_month/cron_day_of_week are mutually exclusive; both
 * null means daily.
 */

import { z } from "zod";

export const SCHEDULED_REPORT_STATUSES = ["active", "paused", "archived"] as const;
export const ScheduledReportStatusSchema = z.enum(SCHEDULED_REPORT_STATUSES);
export type ScheduledReportStatus = z.infer<typeof ScheduledReportStatusSchema>;

export const SCHEDULED_REPORT_RUN_STATUSES = ["queued", "completed", "failed"] as const;
export const ScheduledReportRunStatusSchema = z.enum(SCHEDULED_REPORT_RUN_STATUSES);
export type ScheduledReportRunStatus = z.infer<typeof ScheduledReportRunStatusSchema>;

/** Reuses the same generic flat-record shape IAE-002/IAE-004 already established -- filters ARE the underlying report's own run parameters. */
export const ScheduledReportFiltersSchema = z.record(z.string(), z.union([z.string(), z.number(), z.boolean(), z.null()]));
export type ScheduledReportFilters = z.input<typeof ScheduledReportFiltersSchema>;

export const ScheduledReportSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  reportTypeCode: z.string(),
  ownerAuthUserId: z.string().uuid(),
  name: z.string(),
  description: z.string(),
  cronMinute: z.number().int().min(0).max(59),
  cronHour: z.number().int().min(0).max(23),
  cronDayOfMonth: z.number().int().min(1).max(28).nullable(),
  cronDayOfWeek: z.number().int().min(0).max(6).nullable(),
  timezone: z.string(),
  filters: ScheduledReportFiltersSchema,
  status: ScheduledReportStatusSchema,
  nextRunAt: z.string(),
  lastRunAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ScheduledReport = z.infer<typeof ScheduledReportSchema>;

export function parseScheduledReport(row: Record<string, unknown>): ScheduledReport {
  return ScheduledReportSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    reportTypeCode: row.report_type_code,
    ownerAuthUserId: row.owner_auth_user_id,
    name: row.name,
    description: row.description,
    cronMinute: row.cron_minute,
    cronHour: row.cron_hour,
    cronDayOfMonth: row.cron_day_of_month,
    cronDayOfWeek: row.cron_day_of_week,
    timezone: row.timezone,
    filters: row.filters ?? {},
    status: row.status,
    nextRunAt: row.next_run_at,
    lastRunAt: row.last_run_at,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ScheduledReportRecipientSchema = z.object({
  id: z.string().uuid(),
  scheduledReportId: z.string().uuid(),
  recipientAuthUserId: z.string().uuid(),
  addedByAuthUserId: z.string().uuid().nullable(),
  createdAt: z.string(),
});
export type ScheduledReportRecipient = z.infer<typeof ScheduledReportRecipientSchema>;

export function parseScheduledReportRecipient(row: Record<string, unknown>): ScheduledReportRecipient {
  return ScheduledReportRecipientSchema.parse({
    id: row.id,
    scheduledReportId: row.scheduled_report_id,
    recipientAuthUserId: row.recipient_auth_user_id,
    addedByAuthUserId: row.added_by_auth_user_id,
    createdAt: row.created_at,
  });
}

/** job_id links to the shared app.jobs queue -- retry/DLQ is entirely that already-VERIFIED mechanism's own state, never duplicated here. */
export const ScheduledReportRunSchema = z.object({
  id: z.string().uuid(),
  scheduledReportId: z.string().uuid(),
  jobId: z.string().uuid().nullable(),
  status: ScheduledReportRunStatusSchema,
  recipientsTotal: z.number().int().nonnegative(),
  recipientsReauthorized: z.number().int().nonnegative(),
  recipientsDenied: z.number().int().nonnegative(),
  artifactFileId: z.string().uuid().nullable(),
  artifactExpiresAt: z.string().nullable(),
  errorReason: z.string().nullable(),
  triggeredByAuthUserId: z.string().uuid().nullable(),
  triggeredByLabel: z.string().nullable(),
  startedAt: z.string(),
  completedAt: z.string().nullable(),
});
export type ScheduledReportRun = z.infer<typeof ScheduledReportRunSchema>;

export function parseScheduledReportRun(row: Record<string, unknown>): ScheduledReportRun {
  return ScheduledReportRunSchema.parse({
    id: row.id,
    scheduledReportId: row.scheduled_report_id,
    jobId: row.job_id,
    status: row.status,
    recipientsTotal: row.recipients_total,
    recipientsReauthorized: row.recipients_reauthorized,
    recipientsDenied: row.recipients_denied,
    artifactFileId: row.artifact_file_id,
    artifactExpiresAt: row.artifact_expires_at,
    errorReason: row.error_reason,
    triggeredByAuthUserId: row.triggered_by_auth_user_id,
    triggeredByLabel: row.triggered_by_label,
    startedAt: row.started_at,
    completedAt: row.completed_at,
  });
}

export const CreateScheduledReportInputSchema = z.object({
  tenantId: z.string().uuid(),
  reportTypeCode: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  cronMinute: z.number().int().min(0).max(59),
  cronHour: z.number().int().min(0).max(23),
  cronDayOfMonth: z.number().int().min(1).max(28).nullable().default(null),
  cronDayOfWeek: z.number().int().min(0).max(6).nullable().default(null),
  timezone: z.string().min(1),
  filters: ScheduledReportFiltersSchema.default({}),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateScheduledReportInput = z.input<typeof CreateScheduledReportInputSchema>;

export const SetScheduledReportStatusInputSchema = z.object({
  scheduledReportId: z.string().uuid(),
  status: ScheduledReportStatusSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SetScheduledReportStatusInput = z.input<typeof SetScheduledReportStatusInputSchema>;

export const AddScheduledReportRecipientInputSchema = z.object({
  scheduledReportId: z.string().uuid(),
  recipientAuthUserId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AddScheduledReportRecipientInput = z.input<typeof AddScheduledReportRecipientInputSchema>;

export const RemoveScheduledReportRecipientInputSchema = z.object({
  recipientRowId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RemoveScheduledReportRecipientInput = z.input<typeof RemoveScheduledReportRecipientInputSchema>;

export const RunScheduledReportInputSchema = z.object({
  scheduledReportId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RunScheduledReportInput = z.input<typeof RunScheduledReportInputSchema>;
