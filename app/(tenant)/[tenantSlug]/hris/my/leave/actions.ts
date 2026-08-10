"use server";

/**
 * Self-service Leave/Permit/Business-Trip Server Actions (HRT-280,
 * CG-S12-HRT-008). No employee id is ever accepted from the client here --
 * app.create_leave_request/app.submit_leave_request/app.cancel_leave_request
 * all resolve or verify the acting employee from the caller's own session
 * identity server-side (decision 10/mandatory reading anti-spoofing).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createLeaveRequest, submitLeaveRequest, cancelLeaveRequest, LeaveMutationError } from "../../../../../../server/mutations/leave.ts";
import type { DayPortion } from "../../../../../../server/contracts/leave/leave.ts";

export interface MyLeaveActionState {
  readonly error: string | null;
}

const OK: MyLeaveActionState = { error: null };
const NO_ACCESS: MyLeaveActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/my/leave`;
}

/** Creates a draft, then immediately submits it for approval -- the common case. A caller who only wants a draft can stop after HR/manager review tooling adds a dedicated "save draft" affordance later (disclosed, section 22's "draft" capability is real at the RPC layer even though this form composes both steps). */
export async function requestLeaveAction(tenantSlug: string, _prevState: MyLeaveActionState, formData: FormData): Promise<MyLeaveActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const leaveTypeId = String(formData.get("leaveTypeId") ?? "").trim();
  const dateFrom = String(formData.get("dateFrom") ?? "").trim();
  const dateTo = String(formData.get("dateTo") ?? "").trim();
  const dayPortion = String(formData.get("dayPortion") ?? "full_day") as DayPortion;
  const reason = String(formData.get("reason") ?? "").trim();
  const destination = String(formData.get("destination") ?? "").trim() || null;
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;
  if (!leaveTypeId || !dateFrom || !dateTo || !reason) return { error: "Leave type, date range, and reason are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    const created = await createLeaveRequest(supabase, {
      tenantId: access.tenant.id,
      leaveTypeId,
      dateFrom,
      dateTo,
      dayPortion,
      reason,
      destination,
      evidenceFileId: null,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    const createdRow = created as { id: string; record_version: number };
    await submitLeaveRequest(supabase, {
      requestId: createdRow.id,
      expectedVersion: createdRow.record_version,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not submit this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

/** Resubmits an existing draft (e.g. one returned to draft after rejection) without re-entering every field. */
export async function resubmitLeaveRequestAction(tenantSlug: string, requestId: string, expectedVersion: number, _prevState: MyLeaveActionState, _formData: FormData): Promise<MyLeaveActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitLeaveRequest(supabase, { requestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not resubmit this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelMyLeaveRequestAction(tenantSlug: string, requestId: string, expectedVersion: number, _prevState: MyLeaveActionState, formData: FormData): Promise<MyLeaveActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("cancelReason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel a request." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelLeaveRequest(supabase, { requestId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not cancel this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
