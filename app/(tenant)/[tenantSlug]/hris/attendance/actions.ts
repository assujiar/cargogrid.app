"use server";

/**
 * HR/manager attendance review Server Actions (HRT-278, CG-S12-HRT-006).
 * Every write here is permission-gated at the RPC layer (HRS:Edit/Approve/
 * Override depending on the action's own blast radius, decision 11) --
 * this file never re-implements or weakens that gate, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import type { HrisExportActionState } from "../../../../../components/domain/hris-export-form.tsx";
import { buildHrisExport } from "../../../../../lib/hris/hris-export-action.ts";
import { exportAttendanceSessions } from "../../../../../server/queries/hris-export.ts";
import { ATTENDANCE_SESSION_EXPORT_HEADER, attendanceSessionExportCells } from "../../../../../server/contracts/hris-export/hris-export.ts";
import {
  recordManualAttendanceEvent,
  decideAttendanceCorrection,
  acknowledgeAttendanceException,
  waiveAttendanceException,
  approveAttendanceForPayrollInput,
  recalculateAttendanceExceptions,
  AttendanceMutationError,
} from "../../../../../server/mutations/attendance.ts";
import type { EventType, CorrectionDecision } from "../../../../../server/contracts/attendance/attendance.ts";

export interface AttendanceAdminActionState {
  readonly error: string | null;
}

const OK: AttendanceAdminActionState = { error: null };
const NO_ACCESS: AttendanceAdminActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/attendance`;
}

export async function recordManualEntryAction(tenantSlug: string, _prevState: AttendanceAdminActionState, formData: FormData): Promise<AttendanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const eventType = String(formData.get("eventType") ?? "") as EventType;
  const eventAtRaw = String(formData.get("eventAt") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!employeeId || !eventAtRaw || !reason) return { error: "Employee, event time, and reason are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await recordManualAttendanceEvent(supabase, {
      tenantId: access.tenant.id,
      employeeId,
      eventType,
      eventAt: new Date(eventAtRaw).toISOString(),
      reason,
      idempotencyKey: `manual-${employeeId}-${Date.now()}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not record this manual entry: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decideCorrectionAction(
  tenantSlug: string,
  requestId: string,
  expectedVersion: number,
  decision: CorrectionDecision,
  _prevState: AttendanceAdminActionState,
  formData: FormData,
): Promise<AttendanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  if (!decidedReason) return { error: "A reason is required to approve or reject a correction request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideAttendanceCorrection(supabase, { requestId, expectedVersion, decision, decidedReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not ${decision} this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function acknowledgeExceptionAction(tenantSlug: string, exceptionId: string, expectedVersion: number, _prevState: AttendanceAdminActionState, _formData: FormData): Promise<AttendanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await acknowledgeAttendanceException(supabase, { exceptionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not acknowledge this exception: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function waiveExceptionAction(tenantSlug: string, exceptionId: string, expectedVersion: number, _prevState: AttendanceAdminActionState, formData: FormData): Promise<AttendanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const waiveReason = String(formData.get("waiveReason") ?? "").trim();
  if (!waiveReason) return { error: "A reason is required to waive an exception." };

  const supabase = await createSupabaseServerClient();
  try {
    await waiveAttendanceException(supabase, { exceptionId, expectedVersion, waiveReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not waive this exception: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function approvePayrollInputAction(tenantSlug: string, _prevState: AttendanceAdminActionState, formData: FormData): Promise<AttendanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const fromDate = String(formData.get("fromDate") ?? "").trim();
  const toDate = String(formData.get("toDate") ?? "").trim();
  if (!fromDate || !toDate) return { error: "A from/to date range is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await approveAttendanceForPayrollInput(supabase, { tenantId: access.tenant.id, fromDate, toDate, employeeId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not approve attendance for payroll input: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function recalculateExceptionsAction(tenantSlug: string, _prevState: AttendanceAdminActionState, formData: FormData): Promise<AttendanceAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const fromDate = String(formData.get("fromDate") ?? "").trim();
  const toDate = String(formData.get("toDate") ?? "").trim();
  if (!fromDate || !toDate) return { error: "A from/to date range is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await recalculateAttendanceExceptions(supabase, { tenantId: access.tenant.id, fromDate, toDate, orgUnitId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not recalculate exceptions: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

// ---------------------------------------------------------------------------
// Bulk export (ISS-2026-075). `app.export_attendance_sessions` has been real, `HRS:Export`-gated
// and SQL-tested since HRT-278; until now nothing in the application called it.
// The entry's own disposition asked for all four HRIS exports to be wired in one
// pass rather than piecemeal, which is what this and its three siblings do.
//
// The authority check lives in `server/queries/hris-export.ts`, not here: the RPC
// answers an unauthorised caller with an empty result rather than an error, which
// through a UI reads as "there was nothing to export". This action never sees that
// ambiguity -- it gets a thrown `insufficient_authority` instead.
// ---------------------------------------------------------------------------

export async function exportAttendanceSessionsAction(
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
    filenameStem: "attendance-sessions",
    header: ATTENDANCE_SESSION_EXPORT_HEADER,
    fetchRows: (range) => exportAttendanceSessions(supabase, access.tenant.id, access.authUserId, range),
    toCells: attendanceSessionExportCells,
  });
}
