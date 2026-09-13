/**
 * Scheduled Reports read queries (IAE-006, Prompt 334). All RLS-scoped reads
 * via RPC (O1 remediation, cluster 6) -- app is not exposed to PostgREST. All
 * 4 functions are SECURITY INVOKER, zero actor parameter.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseScheduledReport,
  parseScheduledReportRecipient,
  parseScheduledReportRun,
  type ScheduledReport,
  type ScheduledReportRecipient,
  type ScheduledReportRun,
} from "../contracts/scheduled-report/scheduled-report.ts";

export type ScheduledReportQueryClient = Pick<SupabaseClient, "rpc">;

export class ScheduledReportQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ScheduledReportQueryError";
  }
}

/** Every schedule for one tenant, most recently updated first. */
export async function listScheduledReports(client: ScheduledReportQueryClient, tenantId: string): Promise<ScheduledReport[]> {
  const { data, error } = await client.rpc("list_scheduled_reports", { p_tenant_id: tenantId });
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseScheduledReport(row));
}

/** A single schedule by id -- returns null (never an error) when it does not exist or RLS hides it. */
export async function getScheduledReportById(client: ScheduledReportQueryClient, scheduledReportId: string): Promise<ScheduledReport | null> {
  const { data, error } = await client.rpc("get_scheduled_report_by_id", { p_scheduled_report_id: scheduledReportId });
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseScheduledReport(row as Record<string, unknown>);
}

/** Every recipient of one schedule. */
export async function listScheduledReportRecipients(client: ScheduledReportQueryClient, scheduledReportId: string): Promise<ScheduledReportRecipient[]> {
  const { data, error } = await client.rpc("list_scheduled_report_recipients", { p_scheduled_report_id: scheduledReportId });
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseScheduledReportRecipient(row));
}

/** Run history for one schedule, newest first -- freshness/failure/retry evidence (job_id links to the shared app.jobs queue). */
export async function listScheduledReportRuns(client: ScheduledReportQueryClient, scheduledReportId: string, limit = 25): Promise<ScheduledReportRun[]> {
  const { data, error } = await client.rpc("list_scheduled_report_runs", { p_scheduled_report_id: scheduledReportId, p_limit: limit });
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseScheduledReportRun(row));
}
