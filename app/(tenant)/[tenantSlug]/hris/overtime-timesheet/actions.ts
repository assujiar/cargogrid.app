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
  createTimesheetPeriod,
  lockTimesheetPeriod,
  reopenTimesheetPeriod,
  approveTimesheetPeriodSummary,
  rejectTimesheetPeriodSummary,
  reopenTimesheetPeriodSummary,
  generatePayrollTimeInputsForPeriod,
  OvertimeTimesheetMutationError,
} from "../../../../../server/mutations/overtime-timesheet.ts";
import type { Decision } from "../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";

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
