"use server";

/**
 * Self-service overtime and timesheet Server Actions (HRT-281,
 * CG-S12-HRT-009). Every write here is self-only, structurally -- no
 * employee-id parameter exists on any of the create/submit/cancel RPCs this
 * file forwards to.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createOvertimeRequest,
  submitOvertimeRequest,
  cancelOvertimeRequest,
  createTimesheetEntry,
  submitTimesheetEntry,
  cancelTimesheetEntry,
  submitTimesheetPeriodSummary,
  OvertimeTimesheetMutationError,
} from "../../../../../../server/mutations/overtime-timesheet.ts";
import type { RequestType } from "../../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";

export interface MyOvertimeTimesheetActionState {
  readonly error: string | null;
}

const OK: MyOvertimeTimesheetActionState = { error: null };
const NO_ACCESS: MyOvertimeTimesheetActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/my/overtime-timesheet`;
}

export async function createOvertimeRequestAction(tenantSlug: string, _prevState: MyOvertimeTimesheetActionState, formData: FormData): Promise<MyOvertimeTimesheetActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const requestType = String(formData.get("requestType") ?? "planned") as RequestType;
  const requestedStartAt = String(formData.get("requestedStartAt") ?? "").trim();
  const requestedEndAt = String(formData.get("requestedEndAt") ?? "").trim();
  const unpaidBreakMinutesRaw = String(formData.get("unpaidBreakMinutes") ?? "0").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!requestedStartAt || !requestedEndAt || !reason) return { error: "Start time, end time, and a reason are all required." };
  const unpaidBreakMinutes = Number(unpaidBreakMinutesRaw || "0");
  if (Number.isNaN(unpaidBreakMinutes) || unpaidBreakMinutes < 0) return { error: "Unpaid break minutes must be a non-negative number." };

  const supabase = await createSupabaseServerClient();
  try {
    await createOvertimeRequest(supabase, {
      tenantId: access.tenant.id,
      requestType,
      requestedStartAt: new Date(requestedStartAt).toISOString(),
      requestedEndAt: new Date(requestedEndAt).toISOString(),
      unpaidBreakMinutes,
      reason,
      scheduleAssignmentId: null,
      jobOrderId: null,
      shipmentOrderId: null,
      idempotencyKey: `ot-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not create this overtime request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitOvertimeRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  _prevState: MyOvertimeTimesheetActionState,
  _formData: FormData,
): Promise<MyOvertimeTimesheetActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitOvertimeRequest(supabase, { requestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not submit this overtime request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelOvertimeRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  _prevState: MyOvertimeTimesheetActionState,
  formData: FormData,
): Promise<MyOvertimeTimesheetActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel an overtime request." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelOvertimeRequest(supabase, { requestId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not cancel this overtime request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTimesheetEntryAction(tenantSlug: string, _prevState: MyOvertimeTimesheetActionState, formData: FormData): Promise<MyOvertimeTimesheetActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const workDate = String(formData.get("workDate") ?? "").trim();
  const entryMinutesRaw = String(formData.get("entryMinutes") ?? "").trim();
  const unpaidBreakMinutesRaw = String(formData.get("unpaidBreakMinutes") ?? "0").trim();
  const jobOrderId = String(formData.get("jobOrderId") ?? "").trim() || null;
  const shipmentOrderId = String(formData.get("shipmentOrderId") ?? "").trim() || null;
  const notes = String(formData.get("notes") ?? "").trim() || null;
  const entryMinutes = Number(entryMinutesRaw);
  const unpaidBreakMinutes = Number(unpaidBreakMinutesRaw || "0");
  if (!workDate || !entryMinutesRaw || Number.isNaN(entryMinutes) || entryMinutes <= 0) return { error: "A work date and a positive number of entry minutes are required." };
  if (Number.isNaN(unpaidBreakMinutes) || unpaidBreakMinutes < 0) return { error: "Unpaid break minutes must be a non-negative number." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTimesheetEntry(supabase, {
      tenantId: access.tenant.id,
      workDate,
      entryMinutes,
      unpaidBreakMinutes,
      jobOrderId,
      shipmentOrderId,
      scheduleAssignmentId: null,
      notes,
      idempotencyKey: `ts-${access.authUserId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not create this timesheet entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitTimesheetEntryAction(
  tenantSlug: string,
  entryId: string,
  expectedVersion: number,
  _prevState: MyOvertimeTimesheetActionState,
  _formData: FormData,
): Promise<MyOvertimeTimesheetActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitTimesheetEntry(supabase, { entryId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not submit this timesheet entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelTimesheetEntryAction(
  tenantSlug: string,
  entryId: string,
  expectedVersion: number,
  _prevState: MyOvertimeTimesheetActionState,
  formData: FormData,
): Promise<MyOvertimeTimesheetActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel a timesheet entry." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelTimesheetEntry(supabase, { entryId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not cancel this timesheet entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitTimesheetPeriodSummaryAction(tenantSlug: string, _prevState: MyOvertimeTimesheetActionState, formData: FormData): Promise<MyOvertimeTimesheetActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const periodId = String(formData.get("periodId") ?? "").trim();
  const employeeId = String(formData.get("employeeId") ?? "").trim();
  if (!periodId || !employeeId) return { error: "A period is required (and your own employee profile must be resolvable)." };

  const supabase = await createSupabaseServerClient();
  try {
    await submitTimesheetPeriodSummary(supabase, { periodId, employeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not submit your period summary: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
