"use server";

/**
 * HR/manager Leave/Permit/Business-Trip review Server Actions (HRT-280,
 * CG-S12-HRT-008). Every write here is permission-gated at the RPC layer
 * (HRS:Edit/Approve/Override depending on blast radius, decision 12; the
 * approve/reject decision itself gates through PLT-123's own
 * app.decide_approval_step, decision 6) -- this file never re-implements or
 * weakens that gate, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  decideLeaveRequest,
  adjustLeaveBalance,
  syncEmployeeLeaveLifecycleStatus,
  cancelConflictingScheduleForLeave,
  LeaveMutationError,
} from "../../../../../server/mutations/leave.ts";

export interface LeaveAdminActionState {
  readonly error: string | null;
}

const OK: LeaveAdminActionState = { error: null };
const NO_ACCESS: LeaveAdminActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/leave`;
}

export async function decideLeaveRequestAction(
  tenantSlug: string,
  requestStepId: string,
  decision: "approved" | "rejected",
  _prevState: LeaveAdminActionState,
  formData: FormData,
): Promise<LeaveAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  const overrideCoverage = formData.get("overrideCoverage") === "on";
  if (!reason) return { error: "A reason is required to approve or reject a request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideLeaveRequest(supabase, { requestStepId, decision, reason, overrideCoverage, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not ${decision === "approved" ? "approve" : "reject"} this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function adjustLeaveBalanceAction(tenantSlug: string, _prevState: LeaveAdminActionState, formData: FormData): Promise<LeaveAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const leaveTypeId = String(formData.get("leaveTypeId") ?? "").trim();
  const unitsRaw = String(formData.get("units") ?? "").trim();
  const effectiveDate = String(formData.get("effectiveDate") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const units = Number(unitsRaw);
  if (!employeeId || !leaveTypeId || !unitsRaw || Number.isNaN(units) || units === 0 || !effectiveDate || !reason) {
    return { error: "Employee, leave type, a non-zero units value, effective date, and reason are all required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await adjustLeaveBalance(supabase, {
      tenantId: access.tenant.id,
      employeeId,
      leaveTypeId,
      units,
      effectiveDate,
      reason,
      idempotencyKey: `adjust-${employeeId}-${leaveTypeId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not adjust this balance: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function syncLeaveLifecycleAction(tenantSlug: string, _prevState: LeaveAdminActionState, _formData: FormData): Promise<LeaveAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await syncEmployeeLeaveLifecycleStatus(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not sync employee leave status: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelConflictingScheduleAction(tenantSlug: string, _prevState: LeaveAdminActionState, formData: FormData): Promise<LeaveAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const leaveRequestId = String(formData.get("leaveRequestId") ?? "").trim();
  const workDate = String(formData.get("workDate") ?? "").trim();
  const expectedVersionRaw = String(formData.get("expectedVersion") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim() || null;
  const expectedVersion = Number(expectedVersionRaw);
  if (!leaveRequestId || !workDate || !expectedVersionRaw || Number.isNaN(expectedVersion)) {
    return { error: "The leave request id, work date, and its current version are all required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelConflictingScheduleForLeave(supabase, { leaveRequestId, workDate, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not cancel the conflicting schedule assignment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
