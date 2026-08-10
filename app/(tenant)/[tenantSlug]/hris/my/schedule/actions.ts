"use server";

/**
 * Self-service schedule Server Actions (HRT-279, CG-S12-HRT-007). Every swap
 * request resolves the requesting employee's own identity server-side via
 * app.request_schedule_swap's own identity-match branch -- the client never
 * asserts which employee it is acting as beyond the session itself.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { requestScheduleSwap, cancelScheduleSwapRequest, ShiftRosterMutationError } from "../../../../../../server/mutations/shift-roster.ts";

export interface MyScheduleActionState {
  readonly error: string | null;
}

const OK: MyScheduleActionState = { error: null };
const NO_ACCESS: MyScheduleActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/my/schedule`;
}

export async function requestMySwapAction(tenantSlug: string, _prevState: MyScheduleActionState, formData: FormData): Promise<MyScheduleActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const assignmentId = String(formData.get("assignmentId") ?? "").trim();
  const targetEmployeeId = String(formData.get("targetEmployeeId") ?? "").trim();
  const targetAssignmentId = String(formData.get("targetAssignmentId") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  if (!assignmentId || !targetEmployeeId || !targetAssignmentId || !reason) return { error: "Your own shift, the colleague, their shift, and a reason are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await requestScheduleSwap(supabase, {
      assignmentId,
      targetEmployeeId,
      targetAssignmentId,
      reason,
      idempotencyKey: `swap-${assignmentId}-${targetAssignmentId}`,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not submit this swap request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelMySwapAction(tenantSlug: string, requestId: string, expectedVersion: number, _prevState: MyScheduleActionState, _formData: FormData): Promise<MyScheduleActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await cancelScheduleSwapRequest(supabase, { requestId, expectedVersion, reason: "withdrawn by requester", actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ShiftRosterMutationError) return { error: `Could not cancel this swap request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
