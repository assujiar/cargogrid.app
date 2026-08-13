/**
 * Overtime and Timesheet read queries (HRT-281, CG-S12-HRT-009). Thin, typed
 * wrappers around every read RPC in
 * supabase/migrations/20260730980000_create_hris_overtime_timesheet.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseOvertimeRequestRow,
  parseOvertimeRequestAdminRow,
  parseOvertimeRequestDetail,
  parseTimesheetEntryRow,
  parseTimesheetEntryAdminRow,
  parseTimesheetEntryDetail,
  parseTimesheetPeriodRow,
  parseTimesheetPeriodSummaryRow,
  parseTimesheetPeriodSummaryDetail,
  parseOvertimePolicyRow,
  parseOvertimePolicyVersion,
  parsePayrollTimeInputRow,
  parsePayrollTimeInputDetail,
  type OvertimeRequestRow,
  type OvertimeRequestAdminRow,
  type OvertimeRequestDetail,
  type TimesheetEntryRow,
  type TimesheetEntryAdminRow,
  type TimesheetEntryDetail,
  type TimesheetPeriodRow,
  type TimesheetPeriodSummaryRow,
  type TimesheetPeriodSummaryDetail,
  type OvertimePolicyRow,
  type OvertimePolicyVersion,
  type PayrollTimeInputRow,
  type PayrollTimeInputDetail,
} from "../contracts/overtime-timesheet/overtime-timesheet.ts";

export type OvertimeTimesheetQueryClient = Pick<SupabaseClient, "rpc">;

export class OvertimeTimesheetQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OvertimeTimesheetQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function listMyOvertimeRequests(
  client: OvertimeTimesheetQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { limit?: number; afterId?: string | null },
): Promise<OvertimeRequestRow[]> {
  const { data, error } = await client.rpc("list_my_overtime_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parseOvertimeRequestRow);
}

export async function listOvertimeRequests(
  client: OvertimeTimesheetQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { employeeId?: string | null; status?: string | null; limit?: number; afterId?: string | null },
): Promise<OvertimeRequestAdminRow[]> {
  const { data, error } = await client.rpc("list_overtime_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_employee_id: options?.employeeId ?? null,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parseOvertimeRequestAdminRow);
}

export async function getOvertimeRequestDetail(client: OvertimeTimesheetQueryClient, requestId: string, actorAuthUserId: string): Promise<OvertimeRequestDetail | null> {
  const { data, error } = await client.rpc("get_overtime_request_detail", { p_request_id: requestId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseOvertimeRequestDetail(row) : null;
}

export async function listMyTimesheetEntries(
  client: OvertimeTimesheetQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { fromDate?: string | null; toDate?: string | null; limit?: number; afterId?: string | null },
): Promise<TimesheetEntryRow[]> {
  const { data, error } = await client.rpc("list_my_timesheet_entries", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_from_date: options?.fromDate ?? null,
    p_to_date: options?.toDate ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parseTimesheetEntryRow);
}

export async function listTimesheetEntries(
  client: OvertimeTimesheetQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { employeeId?: string | null; status?: string | null; fromDate?: string | null; toDate?: string | null; limit?: number; afterId?: string | null },
): Promise<TimesheetEntryAdminRow[]> {
  const { data, error } = await client.rpc("list_timesheet_entries", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_employee_id: options?.employeeId ?? null,
    p_status: options?.status ?? null,
    p_from_date: options?.fromDate ?? null,
    p_to_date: options?.toDate ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parseTimesheetEntryAdminRow);
}

export async function getTimesheetEntryDetail(client: OvertimeTimesheetQueryClient, entryId: string, actorAuthUserId: string): Promise<TimesheetEntryDetail | null> {
  const { data, error } = await client.rpc("get_timesheet_entry_detail", { p_entry_id: entryId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTimesheetEntryDetail(row) : null;
}

export async function listTimesheetPeriods(client: OvertimeTimesheetQueryClient, tenantId: string, actorAuthUserId: string): Promise<TimesheetPeriodRow[]> {
  const { data, error } = await client.rpc("list_timesheet_periods", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parseTimesheetPeriodRow);
}

export async function listTimesheetPeriodSummaries(
  client: OvertimeTimesheetQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { periodId?: string | null; status?: string | null },
): Promise<TimesheetPeriodSummaryRow[]> {
  const { data, error } = await client.rpc("list_timesheet_period_summaries", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_period_id: options?.periodId ?? null,
    p_status: options?.status ?? null,
  });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parseTimesheetPeriodSummaryRow);
}

export async function getTimesheetPeriodSummary(client: OvertimeTimesheetQueryClient, summaryId: string, actorAuthUserId: string): Promise<TimesheetPeriodSummaryDetail | null> {
  const { data, error } = await client.rpc("get_timesheet_period_summary", { p_summary_id: summaryId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseTimesheetPeriodSummaryDetail(row) : null;
}

export async function listOvertimePolicies(client: OvertimeTimesheetQueryClient, tenantId: string, actorAuthUserId: string): Promise<OvertimePolicyRow[]> {
  const { data, error } = await client.rpc("list_overtime_policies", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parseOvertimePolicyRow);
}

export async function getOvertimePolicyVersion(client: OvertimeTimesheetQueryClient, versionId: string, actorAuthUserId: string): Promise<OvertimePolicyVersion | null> {
  const { data, error } = await client.rpc("get_overtime_policy_version", { p_version_id: versionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  if (!data) return null;
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseOvertimePolicyVersion(row as Record<string, unknown>) : null;
}

export async function listPayrollTimeInputs(
  client: OvertimeTimesheetQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { periodId?: string | null },
): Promise<PayrollTimeInputRow[]> {
  const { data, error } = await client.rpc("list_payroll_time_inputs", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_period_id: options?.periodId ?? null,
  });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  return rows(data).map(parsePayrollTimeInputRow);
}

export async function getPayrollTimeInput(client: OvertimeTimesheetQueryClient, payrollTimeInputId: string, actorAuthUserId: string): Promise<PayrollTimeInputDetail | null> {
  const { data, error } = await client.rpc("get_payroll_time_input", { p_payroll_time_input_id: payrollTimeInputId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new OvertimeTimesheetQueryError(error.message);
  const row = rows(data)[0];
  return row ? parsePayrollTimeInputDetail(row) : null;
}
