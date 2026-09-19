/**
 * Commercial Reports read queries (COM-159, CG-S7-COM-018), extended by
 * IAE-002 (Reporting Engine, Prompt 330). All RLS-scoped reads via RPC (O1
 * remediation, cluster 6) -- app is not exposed to PostgREST. All 5 functions
 * are SECURITY INVOKER, zero actor parameter.
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

export type ReportQueryTableClient = Pick<SupabaseClient, "rpc">;

export class ReportQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReportQueryError";
  }
}

/** Every active report type, alphabetical by code -- the code-shipped catalogue, not tenant-scoped. */
export async function listActiveReportTypes(client: ReportQueryTableClient): Promise<ReportType[]> {
  const { data, error } = await client.rpc("list_active_report_types");
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportType(row));
}

/** A single report type by code -- returns null (never an error) when it does not exist. */
export async function getReportTypeByCode(client: ReportQueryTableClient, code: string): Promise<ReportType | null> {
  const { data, error } = await client.rpc("get_report_type_by_code", { p_code: code });
  if (error) {
    throw new ReportQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseReportType(row as Record<string, unknown>);
}

/** Run history for one tenant, most recent first -- RLS (report_runs_select_scoped) is the real scope gate. */
export async function listReportRuns(client: ReportQueryTableClient, tenantId: string, limit = 50): Promise<ReportRun[]> {
  const { data, error } = await client.rpc("list_report_runs", { p_tenant_id: tenantId, p_report_type_code: null, p_limit: limit });
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportRun(row));
}

/** Run history for one tenant, filtered to a single report type -- most recent first. */
export async function listReportRunsForType(client: ReportQueryTableClient, tenantId: string, reportTypeCode: string, limit = 50): Promise<ReportRun[]> {
  const { data, error } = await client.rpc("list_report_runs", { p_tenant_id: tenantId, p_report_type_code: reportTypeCode, p_limit: limit });
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportRun(row));
}

/** IAE-002: the full append-only definition-version history for one report type, newest first. */
export async function listReportTypeVersions(client: ReportQueryTableClient, reportTypeCode: string): Promise<ReportTypeVersion[]> {
  const { data, error } = await client.rpc("list_report_type_versions", { p_report_type_code: reportTypeCode });
  if (error) {
    throw new ReportQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseReportTypeVersion(row));
}
