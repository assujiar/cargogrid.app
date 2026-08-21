/**
 * Scheduled Reports read queries (IAE-006, Prompt 334). All direct,
 * RLS-scoped reads -- no wrapper RPC needed, mirroring app.tenant_dashboards'
 * own precedent (IAE-003): the RLS policies already encode the exact
 * visibility this query layer needs.
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

export type ScheduledReportQueryClient = Pick<SupabaseClient, "from">;

export class ScheduledReportQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ScheduledReportQueryError";
  }
}

/** Every schedule for one tenant, most recently updated first. */
export async function listScheduledReports(client: ScheduledReportQueryClient, tenantId: string): Promise<ScheduledReport[]> {
  const { data, error } = await client.from("scheduled_reports").select("*").eq("tenant_id", tenantId).order("updated_at", { ascending: false });
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseScheduledReport(row));
}

/** A single schedule by id -- returns null (never an error) when it does not exist or RLS hides it. */
export async function getScheduledReportById(client: ScheduledReportQueryClient, scheduledReportId: string): Promise<ScheduledReport | null> {
  const { data, error } = await client.from("scheduled_reports").select("*").eq("id", scheduledReportId).maybeSingle();
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseScheduledReport(data as Record<string, unknown>);
}

/** Every recipient of one schedule. */
export async function listScheduledReportRecipients(client: ScheduledReportQueryClient, scheduledReportId: string): Promise<ScheduledReportRecipient[]> {
  const { data, error } = await client.from("scheduled_report_recipients").select("*").eq("scheduled_report_id", scheduledReportId).order("created_at", { ascending: true });
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseScheduledReportRecipient(row));
}

/** Run history for one schedule, newest first -- freshness/failure/retry evidence (job_id links to the shared app.jobs queue). */
export async function listScheduledReportRuns(client: ScheduledReportQueryClient, scheduledReportId: string, limit = 25): Promise<ScheduledReportRun[]> {
  const { data, error } = await client
    .from("scheduled_report_runs")
    .select("*")
    .eq("scheduled_report_id", scheduledReportId)
    .order("started_at", { ascending: false })
    .limit(limit);
  if (error) {
    throw new ScheduledReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseScheduledReportRun(row));
}
