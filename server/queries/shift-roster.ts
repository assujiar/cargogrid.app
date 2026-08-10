/**
 * Shift, Roster and Scheduling read queries (HRT-279, CG-S12-HRT-007). Thin,
 * typed wrappers around every read RPC in
 * supabase/migrations/20260730910000_create_hris_shift_roster_scheduling.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseShiftTemplateRow,
  parseShiftTemplateVersionDetail,
  parseRosterCycleRow,
  parseRosterCycleDetail,
  parseRosterHolidayRow,
  parseCoverageRequirementRow,
  parseCoveragePreviewRow,
  parseMyScheduleRow,
  parseScheduleAssignmentListRow,
  parseScheduleAssignmentDetail,
  parseSwapRequestRow,
  parseMySwapRequestRow,
  type ShiftTemplateRow,
  type ShiftTemplateVersionDetail,
  type RosterCycleRow,
  type RosterCycleDetail,
  type RosterHolidayRow,
  type CoverageRequirementRow,
  type CoveragePreviewRow,
  type MyScheduleRow,
  type ScheduleAssignmentListRow,
  type ScheduleAssignmentDetail,
  type SwapRequestRow,
  type MySwapRequestRow,
} from "../contracts/shift-roster/shift-roster.ts";

export type ShiftRosterQueryClient = Pick<SupabaseClient, "rpc">;

export class ShiftRosterQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ShiftRosterQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export async function getMySchedule(
  client: ShiftRosterQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { fromDate?: string | null; toDate?: string | null },
): Promise<MyScheduleRow[]> {
  const { data, error } = await client.rpc("get_my_schedule", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_from_date: options?.fromDate ?? null,
    p_to_date: options?.toDate ?? null,
  });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseMyScheduleRow);
}

export async function listScheduleAssignments(
  client: ShiftRosterQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { fromDate?: string | null; toDate?: string | null; employeeId?: string | null; status?: string | null; limit?: number; afterId?: string | null },
): Promise<ScheduleAssignmentListRow[]> {
  const { data, error } = await client.rpc("list_schedule_assignments", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_from_date: options?.fromDate ?? null,
    p_to_date: options?.toDate ?? null,
    p_employee_id: options?.employeeId ?? null,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseScheduleAssignmentListRow);
}

export async function getScheduleAssignmentDetail(client: ShiftRosterQueryClient, assignmentId: string, actorAuthUserId: string): Promise<ScheduleAssignmentDetail | null> {
  const { data, error } = await client.rpc("get_schedule_assignment_detail", { p_assignment_id: assignmentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new ShiftRosterQueryError(error.message);
  const row = firstRow(data);
  return row ? parseScheduleAssignmentDetail(row) : null;
}

export async function listShiftTemplates(client: ShiftRosterQueryClient, tenantId: string, actorAuthUserId: string): Promise<ShiftTemplateRow[]> {
  const { data, error } = await client.rpc("list_shift_templates", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseShiftTemplateRow);
}

export async function getShiftTemplateVersionDetail(client: ShiftRosterQueryClient, versionId: string, actorAuthUserId: string): Promise<ShiftTemplateVersionDetail | null> {
  const { data, error } = await client.rpc("get_shift_template_version_detail", { p_version_id: versionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new ShiftRosterQueryError(error.message);
  const row = firstRow(data);
  return row ? parseShiftTemplateVersionDetail(row) : null;
}

export async function listRosterCycles(client: ShiftRosterQueryClient, tenantId: string, actorAuthUserId: string): Promise<RosterCycleRow[]> {
  const { data, error } = await client.rpc("list_roster_cycles", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseRosterCycleRow);
}

export async function getRosterCycleDetail(client: ShiftRosterQueryClient, rosterCycleId: string, actorAuthUserId: string): Promise<RosterCycleDetail | null> {
  const { data, error } = await client.rpc("get_roster_cycle_detail", { p_roster_cycle_id: rosterCycleId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new ShiftRosterQueryError(error.message);
  const row = firstRow(data);
  return row ? parseRosterCycleDetail(row) : null;
}

export async function listRosterHolidays(client: ShiftRosterQueryClient, tenantId: string, actorAuthUserId: string, orgUnitId?: string | null): Promise<RosterHolidayRow[]> {
  const { data, error } = await client.rpc("list_roster_holidays", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_org_unit_id: orgUnitId ?? null });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseRosterHolidayRow);
}

export async function listScheduleCoverageRequirements(client: ShiftRosterQueryClient, tenantId: string, actorAuthUserId: string, orgUnitId?: string | null): Promise<CoverageRequirementRow[]> {
  const { data, error } = await client.rpc("list_schedule_coverage_requirements", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_org_unit_id: orgUnitId ?? null });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseCoverageRequirementRow);
}

export async function getScheduleCoveragePreview(
  client: ShiftRosterQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  orgUnitId: string | null,
  fromDate: string,
  toDate: string,
): Promise<CoveragePreviewRow[]> {
  const { data, error } = await client.rpc("get_schedule_coverage_preview", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_org_unit_id: orgUnitId,
    p_from_date: fromDate,
    p_to_date: toDate,
  });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseCoveragePreviewRow);
}

export async function listScheduleSwapRequests(
  client: ShiftRosterQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { status?: string | null; limit?: number; afterId?: string | null },
): Promise<SwapRequestRow[]> {
  const { data, error } = await client.rpc("list_schedule_swap_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseSwapRequestRow);
}

export async function listMyScheduleSwapRequests(client: ShiftRosterQueryClient, tenantId: string, actorAuthUserId: string): Promise<MySwapRequestRow[]> {
  const { data, error } = await client.rpc("list_my_schedule_swap_requests", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new ShiftRosterQueryError(error.message);
  return rows(data).map(parseMySwapRequestRow);
}
