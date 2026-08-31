"use server";

/**
 * HR/scheduler roster workspace Server Actions (HRT-279, CG-S12-HRT-007).
 * Every write here is permission-gated at the RPC layer (HRS:Edit/Approve/
 * Override depending on the action's own blast radius, decision 5) -- this
 * file never re-implements or weakens that gate, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import type { HrisExportActionState } from "../../../../../components/domain/hris-export-form.tsx";
import { buildHrisExport } from "../../../../../lib/hris/hris-export-action.ts";
import { exportScheduleAssignments } from "../../../../../server/queries/hris-export.ts";
import { SCHEDULE_ASSIGNMENT_EXPORT_HEADER, scheduleAssignmentExportCells } from "../../../../../server/contracts/hris-export/hris-export.ts";
import {
  assignEmployeeSchedule,
  publishScheduleAssignments,
  decideScheduleSwapRequest,
  setRosterHoliday,
  setScheduleCoverageRequirement,
  ShiftRosterMutationError,
} from "../../../../../server/mutations/shift-roster.ts";
import type { SwapDecision } from "../../../../../server/contracts/shift-roster/shift-roster.ts";

export interface RosterAdminActionState {
  readonly error: string | null;
}

const OK: RosterAdminActionState = { error: null };
const NO_ACCESS: RosterAdminActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/roster`;
}

export async function assignEmployeeScheduleAction(tenantSlug: string, _prevState: RosterAdminActionState, formData: FormData): Promise<RosterAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const shiftTemplateVersionId = String(formData.get("shiftTemplateVersionId") ?? "").trim();
  const workDate = String(formData.get("workDate") ?? "").trim();
  if (!employeeId || !shiftTemplateVersionId || !workDate) return { error: "Employee, shift version, and work date are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await assignEmployeeSchedule(supabase, {
      tenantId: access.tenant.id,
      employeeId,
      shiftTemplateVersionId,
      workDate,
      source: "manual",
      idempotencyKey: `manual-assign-${employeeId}-${workDate}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not assign this schedule: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function publishScheduleAssignmentsAction(tenantSlug: string, _prevState: RosterAdminActionState, formData: FormData): Promise<RosterAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const fromDate = String(formData.get("fromDate") ?? "").trim();
  const toDate = String(formData.get("toDate") ?? "").trim();
  if (!fromDate || !toDate) return { error: "A from/to date range is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await publishScheduleAssignments(supabase, { tenantId: access.tenant.id, fromDate, toDate, orgUnitId: null, employeeId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not publish this range: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideSwapAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  decision: SwapDecision,
  _prevState: RosterAdminActionState,
  formData: FormData,
): Promise<RosterAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  if (!decidedReason) return { error: "A reason is required to approve or reject a swap request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideScheduleSwapRequest(supabase, { requestId, expectedVersion, decision, decidedReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not ${decision} this swap request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function setRosterHolidayAction(tenantSlug: string, _prevState: RosterAdminActionState, formData: FormData): Promise<RosterAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const holidayDate = String(formData.get("holidayDate") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim() || null;
  const isWorkingDay = formData.get("isWorkingDay") === "on";
  if (!holidayDate || !name) return { error: "A date and a name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await setRosterHoliday(supabase, { tenantId: access.tenant.id, orgUnitId, holidayDate, name, isWorkingDay, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not save this holiday: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function setCoverageRequirementAction(tenantSlug: string, _prevState: RosterAdminActionState, formData: FormData): Promise<RosterAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim();
  const shiftTemplateId = String(formData.get("shiftTemplateId") ?? "").trim();
  const dayOfWeek = Number(formData.get("dayOfWeek") ?? -1);
  const minHeadcount = Number(formData.get("minHeadcount") ?? -1);
  if (!orgUnitId || !shiftTemplateId || dayOfWeek < 0 || minHeadcount < 0) return { error: "Org unit, shift template, day of week, and a non-negative minimum headcount are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await setScheduleCoverageRequirement(supabase, { tenantId: access.tenant.id, orgUnitId, shiftTemplateId, dayOfWeek, minHeadcount, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not save this coverage requirement: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

// ---------------------------------------------------------------------------
// Bulk export (ISS-2026-075). `app.export_schedule_assignments` has been real, `HRS:Export`-gated
// and SQL-tested since HRT-279; until now nothing in the application called it.
// The entry's own disposition asked for all four HRIS exports to be wired in one
// pass rather than piecemeal, which is what this and its three siblings do.
//
// The authority check lives in `server/queries/hris-export.ts`, not here: the RPC
// answers an unauthorised caller with an empty result rather than an error, which
// through a UI reads as "there was nothing to export". This action never sees that
// ambiguity -- it gets a thrown `insufficient_authority` instead.
// ---------------------------------------------------------------------------

export async function exportScheduleAssignmentsAction(
  tenantSlug: string,
  _prevState: HrisExportActionState,
  formData: FormData,
): Promise<HrisExportActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's HRIS workspace.", csv: null, filename: null, rowCount: 0, token: null };
  }

  const supabase = await createSupabaseServerClient();
  return buildHrisExport({
    fromDate: String(formData.get("fromDate") ?? ""),
    toDate: String(formData.get("toDate") ?? ""),
    filenameStem: "schedule-assignments",
    header: SCHEDULE_ASSIGNMENT_EXPORT_HEADER,
    fetchRows: (range) => exportScheduleAssignments(supabase, access.tenant.id, access.authUserId, range),
    toCells: scheduleAssignmentExportCells,
  });
}
