"use server";

/**
 * HR/manager overtime and timesheet review Server Actions (HRT-281,
 * CG-S12-HRT-009). Every write here is permission-gated at the RPC layer
 * (HRS:Edit/Approve/Override depending on the action's own blast radius) --
 * this file never re-implements or weakens that gate, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  decideOvertimeRequest,
  decideTimesheetEntry,
  createOvertimeRequestForEmployee,
  createTimesheetEntryForEmployee,
  updateTimesheetEntryDraft,
  reconcileOvertimeRequestActual,
  generatePayrollTimeInput,
  createTimesheetPeriod,
  lockTimesheetPeriod,
  reopenTimesheetPeriod,
  approveTimesheetPeriodSummary,
  rejectTimesheetPeriodSummary,
  reopenTimesheetPeriodSummary,
  generatePayrollTimeInputsForPeriod,
  OvertimeTimesheetMutationError,
} from "../../../../../server/mutations/overtime-timesheet.ts";
import type { Decision, RequestType } from "../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";

export interface OvertimeTimesheetAdminActionState {
  readonly error: string | null;
}

const OK: OvertimeTimesheetAdminActionState = { error: null };
const NO_ACCESS: OvertimeTimesheetAdminActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/overtime-timesheet`;
}

export async function decideOvertimeRequestAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  decision: Decision,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  const overrideRaw = String(formData.get("approvedMinutesOverride") ?? "").trim();
  if (!decidedReason) return { error: "A reason is required to approve or reject an overtime request." };
  const approvedMinutesOverride = overrideRaw ? Number(overrideRaw) : null;
  if (overrideRaw && (Number.isNaN(approvedMinutesOverride) || (approvedMinutesOverride ?? -1) < 0)) {
    return { error: "The approved-minutes override, if provided, must be a non-negative number." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await decideOvertimeRequest(supabase, { requestId, expectedVersion, decision, decidedReason, approvedMinutesOverride, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not ${decision} this overtime request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideTimesheetEntryAction(
  tenantSlug: string,
  entryId: string,
  expectedVersion: number,
  decision: Decision,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  if (!decidedReason) return { error: "A reason is required to approve or reject a timesheet entry." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideTimesheetEntry(supabase, { entryId, expectedVersion, decision, decidedReason, approvedMinutesOverride: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not ${decision} this timesheet entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

/**
 * `ISS-2026-076`: the five HR-on-behalf / draft-correction levers below existed as real, tested,
 * authority-gated service wrappers with **no caller anywhere under `app/`**. Until now HR's only
 * lever over an employee's own row was approve or reject — a fixable typo in someone's timesheet
 * had to be rejected and re-entered by the employee, and a plainly wrong overtime request could
 * not be filed on behalf of someone who could not file it themselves.
 *
 * Each action forwards to its RPC and re-checks nothing: `create_*_for_employee` is `HRS:Edit`,
 * `update_timesheet_entry_draft` is owner-or-`HRS:Edit`, `reconcile_overtime_request_actual` is
 * self-or-`HRS:Edit`, and `generate_payroll_time_input` is `HRS:Approve` — all enforced
 * server-side in the database regardless of what this file does. Re-deciding authority here would
 * add a second, weaker copy of a rule that already holds.
 */

/** Minutes come off a form as strings; a blank optional field must mean "unset", never `0` or `NaN`. */
function optionalMinutes(formData: FormData, field: string): number | null | "invalid" {
  const raw = String(formData.get(field) ?? "").trim();
  if (!raw) return null;
  const parsed = Number(raw);
  if (!Number.isInteger(parsed) || parsed < 0) return "invalid";
  return parsed;
}

function optionalText(formData: FormData, field: string): string | null {
  const raw = String(formData.get(field) ?? "").trim();
  return raw ? raw : null;
}

export async function createOvertimeRequestForEmployeeAction(
  tenantSlug: string,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const requestType = String(formData.get("requestType") ?? "").trim() as RequestType;
  const requestedStartAt = String(formData.get("requestedStartAt") ?? "").trim();
  const requestedEndAt = String(formData.get("requestedEndAt") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!employeeId) return { error: "Choose the employee this overtime request is being filed for." };
  if (!requestedStartAt || !requestedEndAt) return { error: "A start and an end time are both required." };
  if (!reason) return { error: "A reason is required when filing an overtime request on someone's behalf." };

  const unpaidBreakMinutes = optionalMinutes(formData, "unpaidBreakMinutes");
  if (unpaidBreakMinutes === "invalid") return { error: "Unpaid break minutes must be a whole number of minutes, zero or more." };

  const supabase = await createSupabaseServerClient();
  try {
    await createOvertimeRequestForEmployee(supabase, {
      tenantId: access.tenant.id,
      employeeId,
      requestType,
      requestedStartAt,
      requestedEndAt,
      unpaidBreakMinutes: unpaidBreakMinutes ?? 0,
      reason,
      scheduleAssignmentId: null,
      jobOrderId: null,
      shipmentOrderId: null,
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not file this overtime request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTimesheetEntryForEmployeeAction(
  tenantSlug: string,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const workDate = String(formData.get("workDate") ?? "").trim();
  const entryMinutesRaw = String(formData.get("entryMinutes") ?? "").trim();
  if (!employeeId) return { error: "Choose the employee this timesheet entry is being recorded for." };
  if (!workDate) return { error: "A work date is required." };
  const entryMinutes = Number(entryMinutesRaw);
  if (!entryMinutesRaw || !Number.isInteger(entryMinutes) || entryMinutes <= 0) {
    return { error: "Worked minutes must be a whole number greater than zero." };
  }

  const unpaidBreakMinutes = optionalMinutes(formData, "unpaidBreakMinutes");
  if (unpaidBreakMinutes === "invalid") return { error: "Unpaid break minutes must be a whole number of minutes, zero or more." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTimesheetEntryForEmployee(supabase, {
      tenantId: access.tenant.id,
      employeeId,
      workDate,
      entryMinutes,
      unpaidBreakMinutes: unpaidBreakMinutes ?? 0,
      jobOrderId: null,
      shipmentOrderId: null,
      scheduleAssignmentId: null,
      notes: optionalText(formData, "notes"),
      idempotencyKey: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not record this timesheet entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function updateTimesheetEntryDraftAction(
  tenantSlug: string,
  entryId: string,
  expectedVersion: number,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const entryMinutesRaw = String(formData.get("entryMinutes") ?? "").trim();
  const entryMinutes = Number(entryMinutesRaw);
  if (!entryMinutesRaw || !Number.isInteger(entryMinutes) || entryMinutes <= 0) {
    return { error: "Worked minutes must be a whole number greater than zero." };
  }
  const unpaidBreakMinutes = optionalMinutes(formData, "unpaidBreakMinutes");
  if (unpaidBreakMinutes === "invalid") return { error: "Unpaid break minutes must be a whole number of minutes, zero or more." };

  const supabase = await createSupabaseServerClient();
  try {
    await updateTimesheetEntryDraft(supabase, {
      entryId,
      expectedVersion,
      entryMinutes,
      unpaidBreakMinutes: unpaidBreakMinutes ?? 0,
      jobOrderId: null,
      shipmentOrderId: null,
      notes: optionalText(formData, "notes"),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not correct this draft entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function reconcileOvertimeRequestActualAction(
  tenantSlug: string,
  requestId: string,
  _prevState: OvertimeTimesheetAdminActionState,
  _formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await reconcileOvertimeRequestActual(supabase, { requestId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not reconcile this overtime request against attendance: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function generatePayrollTimeInputAction(
  tenantSlug: string,
  periodId: string,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  if (!employeeId) return { error: "Choose the employee whose payroll input should be regenerated." };

  const supabase = await createSupabaseServerClient();
  try {
    await generatePayrollTimeInput(supabase, { periodId, employeeId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not generate this employee's payroll input: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createTimesheetPeriodAction(tenantSlug: string, _prevState: OvertimeTimesheetAdminActionState, formData: FormData): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const periodStart = String(formData.get("periodStart") ?? "").trim();
  const periodEnd = String(formData.get("periodEnd") ?? "").trim();
  if (!code || !periodStart || !periodEnd) return { error: "Code, period start, and period end are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createTimesheetPeriod(supabase, { tenantId: access.tenant.id, orgUnitId: null, code, periodStart, periodEnd, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not create this period: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function lockTimesheetPeriodAction(
  tenantSlug: string,
  periodId: string,
  expectedVersion: number,
  _prevState: OvertimeTimesheetAdminActionState,
  _formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await lockTimesheetPeriod(supabase, { periodId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not lock this period: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function reopenTimesheetPeriodAction(
  tenantSlug: string,
  periodId: string,
  expectedVersion: number,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to reopen a locked period." };

  const supabase = await createSupabaseServerClient();
  try {
    await reopenTimesheetPeriod(supabase, { periodId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not reopen this period: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function approveTimesheetPeriodSummaryAction(
  tenantSlug: string,
  summaryId: string,
  expectedVersion: number,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to approve a period summary." };

  const supabase = await createSupabaseServerClient();
  try {
    await approveTimesheetPeriodSummary(supabase, { summaryId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not approve this period summary: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function rejectTimesheetPeriodSummaryAction(
  tenantSlug: string,
  summaryId: string,
  expectedVersion: number,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to reject a period summary." };

  const supabase = await createSupabaseServerClient();
  try {
    await rejectTimesheetPeriodSummary(supabase, { summaryId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not reject this period summary: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function reopenTimesheetPeriodSummaryAction(
  tenantSlug: string,
  summaryId: string,
  expectedVersion: number,
  _prevState: OvertimeTimesheetAdminActionState,
  formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to reopen an approved period summary." };

  const supabase = await createSupabaseServerClient();
  try {
    await reopenTimesheetPeriodSummary(supabase, { summaryId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not reopen this period summary: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function generatePayrollTimeInputsForPeriodAction(
  tenantSlug: string,
  periodId: string,
  _prevState: OvertimeTimesheetAdminActionState,
  _formData: FormData,
): Promise<OvertimeTimesheetAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await generatePayrollTimeInputsForPeriod(supabase, { periodId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OvertimeTimesheetMutationError) return { error: `Could not generate payroll inputs for this period: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
