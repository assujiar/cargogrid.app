/**
 * Leave, Permit and Business Trip read queries (HRT-280, CG-S12-HRT-008).
 * Thin, typed wrappers around every read RPC in
 * supabase/migrations/20260730930000_create_hris_leave_permit_business_trip.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLeaveTypeRow,
  parseLeaveTypePolicyVersion,
  parseEmployeeLeaveBalanceRow,
  parseLeaveRequestListRow,
  parseLeaveRequestDetail,
  parseLeaveBalanceLedgerRow,
  parseLeaveCalendarRow,
  type LeaveTypeRow,
  type LeaveTypePolicyVersion,
  type EmployeeLeaveBalanceRow,
  type LeaveRequestListRow,
  type LeaveRequestDetail,
  type LeaveBalanceLedgerRow,
  type LeaveCalendarRow,
} from "../contracts/leave/leave.ts";
import { listPendingApprovalStepsForActor, type ApprovalQueryRpcClient } from "./approval.ts";

export type LeaveQueryClient = Pick<SupabaseClient, "rpc" | "from">;

export class LeaveQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LeaveQueryError";
  }
}

/** Supabase's own `.rpc()` returns a `PostgrestFilterBuilder` (thenable, not a strict `Promise`) -- the same adapter server/queries/credit.ts (COM-157) already uses for the identical mismatch. */
function toApprovalQueryRpcClient(client: LeaveQueryClient): ApprovalQueryRpcClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function listLeaveTypes(client: LeaveQueryClient, tenantId: string, actorAuthUserId: string): Promise<LeaveTypeRow[]> {
  const { data, error } = await client.rpc("list_leave_types", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LeaveQueryError(error.message);
  return rows(data).map(parseLeaveTypeRow);
}

export async function listLeaveTypePolicyVersions(client: LeaveQueryClient, leaveTypeId: string, actorAuthUserId: string): Promise<LeaveTypePolicyVersion[]> {
  const { data, error } = await client.rpc("list_leave_type_policy_versions", { p_leave_type_id: leaveTypeId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LeaveQueryError(error.message);
  return rows(data).map(parseLeaveTypePolicyVersion);
}

export async function listEmployeeLeaveBalances(
  client: LeaveQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { employeeId?: string | null; asOfDate?: string | null },
): Promise<EmployeeLeaveBalanceRow[]> {
  const { data, error } = await client.rpc("list_employee_leave_balances", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_employee_id: options?.employeeId ?? null,
    p_as_of_date: options?.asOfDate ?? null,
  });
  if (error) throw new LeaveQueryError(error.message);
  return rows(data).map(parseEmployeeLeaveBalanceRow);
}

export async function listLeaveRequests(
  client: LeaveQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { employeeId?: string | null; status?: string | null; fromDate?: string | null; toDate?: string | null; limit?: number; afterId?: string | null },
): Promise<LeaveRequestListRow[]> {
  const { data, error } = await client.rpc("list_leave_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_employee_id: options?.employeeId ?? null,
    p_status: options?.status ?? null,
    p_from_date: options?.fromDate ?? null,
    p_to_date: options?.toDate ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new LeaveQueryError(error.message);
  return rows(data).map(parseLeaveRequestListRow);
}

export async function getLeaveRequestDetail(client: LeaveQueryClient, requestId: string, actorAuthUserId: string): Promise<LeaveRequestDetail | null> {
  const { data, error } = await client.rpc("get_leave_request_detail", { p_request_id: requestId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new LeaveQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseLeaveRequestDetail(row) : null;
}

export async function listLeaveBalanceLedger(
  client: LeaveQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  employeeId: string,
  options?: { leaveTypeId?: string | null; limit?: number },
): Promise<LeaveBalanceLedgerRow[]> {
  const { data, error } = await client.rpc("list_leave_balance_ledger", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_employee_id: employeeId,
    p_leave_type_id: options?.leaveTypeId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) throw new LeaveQueryError(error.message);
  return rows(data).map(parseLeaveBalanceLedgerRow);
}

export interface LeaveApprovalInboxItem {
  readonly stepId: string;
  readonly stepOrder: number;
  readonly requestId: string;
  readonly leaveRequestId: string;
}

/** The pending-approver inbox, filtered to leave_request-entity requests only -- app.list_pending_approval_steps_for_actor (PLT-123) is entity-agnostic, so this resolves each pending step's own request via a direct, RLS-scoped select on app.approval_requests (no new SQL), mirroring listCreditProfileApprovalInboxForActor (COM-157) exactly. */
export async function listLeaveApprovalInboxForActor(client: LeaveQueryClient, tenantId: string, actorAuthUserId: string): Promise<LeaveApprovalInboxItem[]> {
  const steps = await listPendingApprovalStepsForActor(toApprovalQueryRpcClient(client), { tenantId, actorAuthUserId });
  if (steps.length === 0) {
    return [];
  }

  const requestIds = [...new Set(steps.map((step) => step.requestId))];
  const { data, error } = await client.from("approval_requests").select("id, entity_type, entity_id").in("id", requestIds);
  if (error) throw new LeaveQueryError(error.message);

  const leaveRequestIdByRequestId = new Map<string, string>();
  for (const row of (data ?? []) as Array<{ id: string; entity_type: string; entity_id: string | null }>) {
    if (row.entity_type === "leave_request" && row.entity_id) {
      leaveRequestIdByRequestId.set(row.id, row.entity_id);
    }
  }

  return steps
    .filter((step) => leaveRequestIdByRequestId.has(step.requestId))
    .map((step) => ({
      stepId: step.id,
      stepOrder: step.stepOrder,
      requestId: step.requestId,
      leaveRequestId: leaveRequestIdByRequestId.get(step.requestId)!,
    }));
}

export async function getLeaveCalendar(
  client: LeaveQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  orgUnitId: string | null,
  fromDate: string,
  toDate: string,
): Promise<LeaveCalendarRow[]> {
  const { data, error } = await client.rpc("get_leave_calendar", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_org_unit_id: orgUnitId,
    p_from_date: fromDate,
    p_to_date: toDate,
  });
  if (error) throw new LeaveQueryError(error.message);
  return rows(data).map(parseLeaveCalendarRow);
}
