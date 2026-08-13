"use server";

/**
 * Employee self-service KPI and Performance Server Actions (HRT-283,
 * CG-S12-HRT-011). Every write resolves the caller's own employee_id
 * server-side (self-identity RPCs, or an explicit cycle_id with no
 * employee_id parameter to spoof) -- never a client-supplied employee id.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  recordPerformanceGoalProgress,
  upsertPerformanceAssessmentKpiScore,
  submitPerformanceSelfAssessment,
  acknowledgePerformanceOutcome,
  submitPerformanceAppeal,
  PerformanceMutationError,
} from "../../../../../../server/mutations/kpi-performance.ts";

export interface MyPerformanceActionState {
  readonly error: string | null;
}

const OK: MyPerformanceActionState = { error: null };
const NO_ACCESS: MyPerformanceActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/my/kpi-performance`;
}

export async function recordMyPerformanceGoalProgressAction(tenantSlug: string, goalAssignmentId: string, _prevState: MyPerformanceActionState, formData: FormData): Promise<MyPerformanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const actualValueRaw = String(formData.get("actualValue") ?? "").trim();
  const note = String(formData.get("note") ?? "").trim() || null;
  if (!actualValueRaw && !note) return { error: "Enter an actual value or a note." };

  const supabase = await createSupabaseServerClient();
  try {
    await recordPerformanceGoalProgress(supabase, { goalAssignmentId, actualValue: actualValueRaw ? Number(actualValueRaw) : null, note, evidenceFileId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not record this progress update: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function scoreMyPerformanceGoalAction(tenantSlug: string, assessmentId: string, goalAssignmentId: string, _prevState: MyPerformanceActionState, formData: FormData): Promise<MyPerformanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const actualValueRaw = String(formData.get("actualValue") ?? "").trim();
  const manualScoreRaw = String(formData.get("manualScore") ?? "").trim();
  const scoreRationale = String(formData.get("scoreRationale") ?? "").trim();
  if (!scoreRationale) return { error: "A score rationale is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await upsertPerformanceAssessmentKpiScore(supabase, {
      assessmentId, goalAssignmentId, actualValue: actualValueRaw ? Number(actualValueRaw) : null, manualScore: manualScoreRaw ? Number(manualScoreRaw) : null,
      scoreRationale, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not record this self-assessment score: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitMySelfAssessmentAction(tenantSlug: string, cycleId: string, expectedVersion: number, _prevState: MyPerformanceActionState, formData: FormData): Promise<MyPerformanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const overallComment = String(formData.get("overallComment") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await submitPerformanceSelfAssessment(supabase, { cycleId, expectedVersion, overallComment, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not submit your self assessment: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function acknowledgeMyPerformanceOutcomeAction(
  tenantSlug: string, outcomeId: string, expectedVersion: number, agreement: "agree" | "disagree", _prevState: MyPerformanceActionState, formData: FormData,
): Promise<MyPerformanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const comment = String(formData.get("comment") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await acknowledgePerformanceOutcome(supabase, { outcomeId, expectedVersion, agreement, comment, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not acknowledge this outcome: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitMyPerformanceAppealAction(tenantSlug: string, outcomeId: string, _prevState: MyPerformanceActionState, formData: FormData): Promise<MyPerformanceActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const appealReason = String(formData.get("appealReason") ?? "").trim();
  if (!appealReason) return { error: "An appeal reason is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await submitPerformanceAppeal(supabase, { outcomeId, appealReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PerformanceMutationError) return { error: `Could not submit this appeal: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
