"use server";

/**
 * Self-service attendance Server Actions (HRT-278, CG-S12-HRT-006). Every
 * clock action resolves the acting employee from the caller's own session
 * identity server-side (decision 10) -- no employee id is ever accepted from
 * the client here.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { recordAttendanceClockEvent, requestAttendanceCorrection, cancelAttendanceCorrection, AttendanceMutationError } from "../../../../../../server/mutations/attendance.ts";
import type { EventType, CorrectionRequestType } from "../../../../../../server/contracts/attendance/attendance.ts";

export interface AttendanceActionState {
  readonly error: string | null;
}

const OK: AttendanceActionState = { error: null };
const NO_ACCESS: AttendanceActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/my/attendance`;
}

export async function clockAction(tenantSlug: string, _prevState: AttendanceActionState, formData: FormData): Promise<AttendanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const eventType = String(formData.get("eventType") ?? "") as EventType;
  const sourceChannel = (String(formData.get("sourceChannel") ?? "mobile_web") === "kiosk" ? "kiosk" : "mobile_web") as "mobile_web" | "kiosk";
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;
  const latRaw = String(formData.get("lat") ?? "").trim();
  const lonRaw = String(formData.get("lon") ?? "").trim();
  const locationGeojson = latRaw && lonRaw && Number.isFinite(Number(latRaw)) && Number.isFinite(Number(lonRaw)) ? { type: "Point" as const, coordinates: [Number(lonRaw), Number(latRaw)] as [number, number] } : null;

  const supabase = await createSupabaseServerClient();
  try {
    await recordAttendanceClockEvent(supabase, {
      tenantId: access.tenant.id,
      eventType,
      sourceChannel,
      clientReportedAt: new Date().toISOString(),
      locationGeojson,
      deviceLabel: null,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not record this ${eventType === "clock_in" ? "clock-in" : "clock-out"}: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function requestMyCorrectionAction(tenantSlug: string, _prevState: AttendanceActionState, formData: FormData): Promise<AttendanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const sessionId = String(formData.get("sessionId") ?? "").trim();
  const requestType = String(formData.get("requestType") ?? "") as CorrectionRequestType;
  const proposedTime = String(formData.get("proposedTime") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;

  if (!sessionId || !proposedTime || !reason) return { error: "Session, proposed time, and reason are all required." };

  const proposedClockInAt = requestType === "add_missing_clock_in" || requestType === "adjust_clock_in" ? new Date(proposedTime).toISOString() : null;
  const proposedClockOutAt = requestType === "add_missing_clock_out" || requestType === "adjust_clock_out" ? new Date(proposedTime).toISOString() : null;

  const supabase = await createSupabaseServerClient();
  try {
    await requestAttendanceCorrection(supabase, {
      sessionId,
      requestType,
      proposedClockInAt,
      proposedClockOutAt,
      reason,
      evidenceFileId: null,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not submit this correction request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelMyCorrectionAction(tenantSlug: string, requestId: string, expectedVersion: number): Promise<AttendanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await cancelAttendanceCorrection(supabase, { requestId, expectedVersion, reason: "withdrawn by requester", actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AttendanceMutationError) return { error: `Could not cancel this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
