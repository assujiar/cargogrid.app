/**
 * Analytics and Materialized Views contract (IAE-005, Prompt 333). Mirrors
 * supabase/migrations/20260802040000_create_intelligence_analytics_materialized_views.sql's
 * app.analytics_view_registry/app.analytics_refresh_runs shape, plus the
 * report_usage_daily row shape app.get_report_usage_daily returns.
 */

import { z } from "zod";

export const ANALYTICS_VIEW_STATUSES = ["active", "retired"] as const;
export const AnalyticsViewStatusSchema = z.enum(ANALYTICS_VIEW_STATUSES);
export type AnalyticsViewStatus = z.infer<typeof AnalyticsViewStatusSchema>;

export const ANALYTICS_REFRESH_RUN_STATUSES = ["running", "completed", "failed"] as const;
export const AnalyticsRefreshRunStatusSchema = z.enum(ANALYTICS_REFRESH_RUN_STATUSES);
export type AnalyticsRefreshRunStatus = z.infer<typeof AnalyticsRefreshRunStatusSchema>;

export const AnalyticsViewRegistrySchema = z.object({
  id: z.string().uuid(),
  viewCode: z.string(),
  viewName: z.string(),
  name: z.string(),
  description: z.string(),
  sourceDomain: z.string(),
  refreshFrequencyMinutes: z.number().int().positive(),
  status: AnalyticsViewStatusSchema,
  registeredByAuthUserId: z.string().uuid().nullable(),
  registeredBy: z.string().nullable(),
  createdAt: z.string(),
});
export type AnalyticsViewRegistry = z.infer<typeof AnalyticsViewRegistrySchema>;

export function parseAnalyticsViewRegistry(row: Record<string, unknown>): AnalyticsViewRegistry {
  return AnalyticsViewRegistrySchema.parse({
    id: row.id,
    viewCode: row.view_code,
    viewName: row.view_name,
    name: row.name,
    description: row.description,
    sourceDomain: row.source_domain,
    refreshFrequencyMinutes: row.refresh_frequency_minutes,
    status: row.status,
    registeredByAuthUserId: row.registered_by_auth_user_id,
    registeredBy: row.registered_by,
    createdAt: row.created_at,
  });
}

/** Freshness/lineage/reconciliation evidence for one refresh -- the latest row per viewCode is the current freshness signal a consumer reads. */
export const AnalyticsRefreshRunSchema = z.object({
  id: z.string().uuid(),
  viewCode: z.string(),
  status: AnalyticsRefreshRunStatusSchema,
  rowCountBefore: z.number().int().nonnegative().nullable(),
  rowCountAfter: z.number().int().nonnegative().nullable(),
  reconciled: z.boolean().nullable(),
  errorReason: z.string().nullable(),
  triggeredByAuthUserId: z.string().uuid().nullable(),
  triggeredByLabel: z.string().nullable(),
  startedAt: z.string(),
  completedAt: z.string().nullable(),
});
export type AnalyticsRefreshRun = z.infer<typeof AnalyticsRefreshRunSchema>;

export function parseAnalyticsRefreshRun(row: Record<string, unknown>): AnalyticsRefreshRun {
  return AnalyticsRefreshRunSchema.parse({
    id: row.id,
    viewCode: row.view_code,
    status: row.status,
    rowCountBefore: row.row_count_before,
    rowCountAfter: row.row_count_after,
    reconciled: row.reconciled,
    errorReason: row.error_reason,
    triggeredByAuthUserId: row.triggered_by_auth_user_id,
    triggeredByLabel: row.triggered_by_label,
    startedAt: row.started_at,
    completedAt: row.completed_at,
  });
}

export const ReportUsageDailyRowSchema = z.object({
  reportTypeCode: z.string(),
  usageDate: z.string(),
  previewCount: z.coerce.number().int().nonnegative(),
  exportCount: z.coerce.number().int().nonnegative(),
  failedCount: z.coerce.number().int().nonnegative(),
  lastRunAt: z.string(),
});
export type ReportUsageDailyRow = z.infer<typeof ReportUsageDailyRowSchema>;

export function parseReportUsageDailyRow(row: Record<string, unknown>): ReportUsageDailyRow {
  return ReportUsageDailyRowSchema.parse({
    reportTypeCode: row.report_type_code,
    usageDate: row.usage_date,
    previewCount: row.preview_count,
    exportCount: row.export_count,
    failedCount: row.failed_count,
    lastRunAt: row.last_run_at,
  });
}

export const RegisterAnalyticsViewInputSchema = z.object({
  viewCode: z.string().min(1),
  viewName: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable().default(null),
  sourceDomain: z.string().min(1),
  refreshFrequencyMinutes: z.number().int().positive().default(60),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RegisterAnalyticsViewInput = z.input<typeof RegisterAnalyticsViewInputSchema>;

export const RefreshAnalyticsViewInputSchema = z.object({
  viewCode: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RefreshAnalyticsViewInput = z.input<typeof RefreshAnalyticsViewInputSchema>;
