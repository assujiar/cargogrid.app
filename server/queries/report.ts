/**
 * Commercial Reports read queries (COM-159, CG-S7-COM-018), extended by
 * IAE-002 (Reporting Engine, Prompt 330). Thin, typed wrappers around direct
 * RLS-scoped selects on app.report_types (global catalogue), app.report_runs
 * (tenant-wide visibility) and app.report_type_versions (append-only
 * definition-version history) -- see the migrations' own headers.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseReportType,
  parseReportRun,
  parseReportTypeVersion,
  type ReportType,
  type ReportRun,
  type ReportTypeVersion,
} from "../contracts/report/report.ts";

export type ReportQueryTableClient = Pick<SupabaseClient, "from">;

export class ReportQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReportQueryError";
  }
}

/** Every active report type, alphabetical by code -- the code-shipped catalogue, not tenant-scoped. */
export async function listActiveReportTypes(client: ReportQueryTableClient): Promise<ReportType[]> {
  const { data, error } = await client.from("report_types").select("*").eq("status", "active").order("code", { ascending: true });
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportType(row));
}

/** A single report type by code -- returns null (never an error) when it does not exist. */
export async function getReportTypeByCode(client: ReportQueryTableClient, code: string): Promise<ReportType | null> {
  const { data, error } = await client.from("report_types").select("*").eq("code", code).maybeSingle();
  if (error) {
    throw new ReportQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseReportType(data as Record<string, unknown>);
}

/** Run history for one tenant, most recent first -- RLS (report_runs_select_scoped) is the real scope gate. */
export async function listReportRuns(client: ReportQueryTableClient, tenantId: string, limit = 50): Promise<ReportRun[]> {
  const { data, error } = await client
    .from("report_runs")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("requested_at", { ascending: false })
    .limit(limit);
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportRun(row));
}

/** Run history for one tenant, filtered to a single report type -- most recent first. */
export async function listReportRunsForType(client: ReportQueryTableClient, tenantId: string, reportTypeCode: string, limit = 50): Promise<ReportRun[]> {
  const { data, error } = await client
    .from("report_runs")
    .select("*")
    .eq("tenant_id", tenantId)
    .eq("report_type_code", reportTypeCode)
    .order("requested_at", { ascending: false })
    .limit(limit);
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportRun(row));
}

/** IAE-002: the full append-only definition-version history for one report type, newest first. */
export async function listReportTypeVersions(client: ReportQueryTableClient, reportTypeCode: string): Promise<ReportTypeVersion[]> {
  const { data, error } = await client
    .from("report_type_versions")
    .select("*")
    .eq("report_type_code", reportTypeCode)
    .order("version_number", { ascending: false });
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportTypeVersion(row));
}
