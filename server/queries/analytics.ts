/**
 * Analytics and Materialized Views read queries (IAE-005, Prompt 333).
 * `getReportUsageDaily` calls app.get_report_usage_daily (RPC) -- the only
 * real read path into app.mv_report_usage_daily, which carries zero direct
 * grants. The registry/refresh-run tables are direct, non-RLS reads
 * (non-sensitive platform metadata, mirroring app.report_types' own
 * no-RLS precedent).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseAnalyticsViewRegistry,
  parseAnalyticsRefreshRun,
  parseReportUsageDailyRow,
  type AnalyticsViewRegistry,
  type AnalyticsRefreshRun,
  type ReportUsageDailyRow,
} from "../contracts/analytics/analytics.ts";

export type AnalyticsQueryClient = Pick<SupabaseClient, "from" | "rpc">;

export class AnalyticsQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AnalyticsQueryError";
  }
}

/** Every registered analytics view -- the code-shipped registry, not tenant-scoped. */
export async function listAnalyticsViews(client: AnalyticsQueryClient): Promise<AnalyticsViewRegistry[]> {
  const { data, error } = await client.from("analytics_view_registry").select("*").order("view_code", { ascending: true });
  if (error) {
    throw new AnalyticsQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseAnalyticsViewRegistry(row));
}

/** The freshness signal for one view -- its own latest refresh run, newest first, or null if it has never been refreshed. */
export async function getLatestAnalyticsRefreshRun(client: AnalyticsQueryClient, viewCode: string): Promise<AnalyticsRefreshRun | null> {
  const { data, error } = await client
    .from("analytics_refresh_runs")
    .select("*")
    .eq("view_code", viewCode)
    .order("started_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error) {
    throw new AnalyticsQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseAnalyticsRefreshRun(data as Record<string, unknown>);
}

/** The full refresh-run history for one view, newest first -- lineage/reconciliation evidence, never rewritten. */
export async function listAnalyticsRefreshRuns(client: AnalyticsQueryClient, viewCode: string, limit = 25): Promise<AnalyticsRefreshRun[]> {
  const { data, error } = await client
    .from("analytics_refresh_runs")
    .select("*")
    .eq("view_code", viewCode)
    .order("started_at", { ascending: false })
    .limit(limit);
  if (error) {
    throw new AnalyticsQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseAnalyticsRefreshRun(row));
}

/** The ONLY read path into app.mv_report_usage_daily -- tenant-filtered and authority-checked inside the RPC itself. */
export async function getReportUsageDaily(
  client: AnalyticsQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { reportTypeCode?: string | null; fromDate?: string | null; toDate?: string | null },
): Promise<ReportUsageDailyRow[]> {
  const { data, error } = await client.rpc("get_report_usage_daily", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_report_type_code: options?.reportTypeCode ?? null,
    p_from_date: options?.fromDate ?? null,
    p_to_date: options?.toDate ?? null,
  });
  if (error) {
    throw new AnalyticsQueryError(error.message);
  }
  return ((data ?? []) as Record<string, unknown>[]).map((row) => parseReportUsageDailyRow(row));
}
