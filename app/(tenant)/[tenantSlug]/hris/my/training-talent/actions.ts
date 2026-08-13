"use server";

/**
 * Employee self-service Training and Talent Server Actions (HRT-284,
 * CG-S12-HRT-012). Enrollment resolves the caller's own employee_id
 * server-side via app.enroll_self_in_training_session's own
 * app.get_self_employee call -- no employee-id parameter exists on any
 * self-service RPC this file calls, structurally impossible to spoof.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  enrollSelfInTrainingSession,
  cancelTrainingEnrollment,
  rescheduleTrainingEnrollment,
  updateTrainingDevelopmentPlanActionStatus,
  submitTalentReview,
  TrainingTalentMutationError,
} from "../../../../../../server/mutations/training-talent.ts";

export interface MyTrainingTalentActionState {
  readonly error: string | null;
}

const OK: MyTrainingTalentActionState = { error: null };
const NO_ACCESS: MyTrainingTalentActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/my/training-talent`;
}

export async function enrollSelfInTrainingSessionAction(tenantSlug: string, sessionId: string, _prevState: MyTrainingTalentActionState, _formData: FormData): Promise<MyTrainingTalentActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await enrollSelfInTrainingSession(supabase, { tenantId: access.tenant.id, sessionId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not enroll in this session: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelMyTrainingEnrollmentAction(tenantSlug: string, enrollmentId: string, expectedVersion: number, _prevState: MyTrainingTalentActionState, formData: FormData): Promise<MyTrainingTalentActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel your enrollment." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelTrainingEnrollment(supabase, { enrollmentId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not cancel this enrollment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function rescheduleMyTrainingEnrollmentAction(tenantSlug: string, enrollmentId: string, _prevState: MyTrainingTalentActionState, formData: FormData): Promise<MyTrainingTalentActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const newSessionId = String(formData.get("newSessionId") ?? "").trim();
  if (!newSessionId) return { error: "A new session id is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await rescheduleTrainingEnrollment(supabase, { enrollmentId, newSessionId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not reschedule this enrollment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function updateMyDevelopmentPlanActionStatusAction(
  tenantSlug: string, actionId: string, expectedVersion: number, _prevState: MyTrainingTalentActionState, formData: FormData,
): Promise<MyTrainingTalentActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const status = String(formData.get("status") ?? "in_progress");
  const completedNote = String(formData.get("completedNote") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await updateTrainingDevelopmentPlanActionStatus(supabase, { actionId, expectedVersion, status, completedNote, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not update this action: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitMyTalentReviewAction(tenantSlug: string, reviewId: string, expectedVersion: number, _prevState: MyTrainingTalentActionState, formData: FormData): Promise<MyTrainingTalentActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const potentialRating = String(formData.get("potentialRating") ?? "") as "low" | "moderate" | "high";
  const readinessNote = String(formData.get("readinessNote") ?? "").trim() || null;
  const riskOfLossRaw = String(formData.get("riskOfLoss") ?? "").trim();
  if (!potentialRating) return { error: "A potential rating is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await submitTalentReview(supabase, {
      reviewId, expectedVersion, potentialRating, readinessNote,
      riskOfLoss: (riskOfLossRaw as "low" | "medium" | "high") || null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrainingTalentMutationError) return { error: `Could not submit this review: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
