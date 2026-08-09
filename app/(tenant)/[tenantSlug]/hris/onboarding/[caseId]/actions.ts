"use server";

/**
 * Onboarding/offboarding case detail Server Actions (HRT-277, CG-S12-HRT-005).
 * Every write RPC this workspace exposes: assign/complete/waive/reopen task,
 * provision-request/revoke-request (the real Platform-identity-authority
 * writes, section 16), submit/decide finalize approval, cancel.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { requireOnboardingAccess } from "../actions.ts";
import {
  assignOnboardingTask,
  completeOnboardingTask,
  waiveOnboardingTask,
  reopenOnboardingTask,
  requestOnboardingAccessProvisioning,
  requestOnboardingAccessRevocation,
  submitOnboardingCaseForFinalizeApproval,
  decideOnboardingCaseFinalizeApproval,
  cancelOnboardingCase,
  rehireEmployee,
  OnboardingMutationError,
} from "../../../../../../server/mutations/onboarding.ts";
import type { ApprovalDecision } from "../../../../../../server/contracts/onboarding/onboarding.ts";

export interface OnboardingCaseActionState {
  readonly error: string | null;
}

const OK: OnboardingCaseActionState = { error: null };
const NO_ACCESS: OnboardingCaseActionState = { error: "You don't have access to this organization's HRIS workspace." };

function casePath(tenantSlug: string, caseId: string): string {
  return `/${tenantSlug}/hris/onboarding/${caseId}`;
}

export async function assignOnboardingTaskAction(
  tenantSlug: string,
  caseId: string,
  taskId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const ownerAuthUserId = String(formData.get("ownerAuthUserId") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await assignOnboardingTask(supabase, { caseId, taskId, expectedVersion, ownerAuthUserId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not assign this task: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function completeOnboardingTaskAction(
  tenantSlug: string,
  caseId: string,
  taskId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const evidenceNote = String(formData.get("evidenceNote") ?? "").trim() || null;
  const evidenceFileId = String(formData.get("evidenceFileId") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await completeOnboardingTask(supabase, { caseId, taskId, expectedVersion, evidenceNote, evidenceFileId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not complete this task: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function waiveOnboardingTaskAction(
  tenantSlug: string,
  caseId: string,
  taskId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const waiveReason = String(formData.get("waiveReason") ?? "").trim();
  if (!waiveReason) return { error: "A reason is required to waive a task." };

  const supabase = await createSupabaseServerClient();
  try {
    await waiveOnboardingTask(supabase, { caseId, taskId, expectedVersion, waiveReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not waive this task: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function reopenOnboardingTaskAction(
  tenantSlug: string,
  caseId: string,
  taskId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to reopen a task." };

  const supabase = await createSupabaseServerClient();
  try {
    await reopenOnboardingTask(supabase, { caseId, taskId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not reopen this task: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function requestAccessProvisioningAction(
  tenantSlug: string,
  caseId: string,
  taskId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const targetAuthUserId = String(formData.get("targetAuthUserId") ?? "").trim() || null;
  const roleVersionIdsRaw = String(formData.get("roleVersionIds") ?? "").trim();
  const roleVersionIds = roleVersionIdsRaw ? roleVersionIdsRaw.split(",").map((s) => s.trim()).filter(Boolean) : [];
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await requestOnboardingAccessProvisioning(supabase, { caseId, taskId, expectedVersion, targetAuthUserId, roleVersionIds, orgUnitId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not request access provisioning: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function requestAccessRevocationAction(
  tenantSlug: string,
  caseId: string,
  taskId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  _formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await requestOnboardingAccessRevocation(supabase, { caseId, taskId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not request access revocation: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function submitFinalizeApprovalAction(
  tenantSlug: string,
  caseId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const exitReason = String(formData.get("exitReason") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    await submitOnboardingCaseForFinalizeApproval(supabase, { caseId, expectedVersion, exitReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not submit for finalize approval: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function decideFinalizeApprovalAction(
  tenantSlug: string,
  caseId: string,
  requestStepId: string,
  decision: ApprovalDecision,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const reason = String(formData.get("reason") ?? "").trim() || null;
  if (decision === "rejected" && !reason) return { error: "A reason is required to reject a finalize decision." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideOnboardingCaseFinalizeApproval(supabase, { requestStepId, decision, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not record this decision: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

export async function cancelOnboardingCaseAction(
  tenantSlug: string,
  caseId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel a case." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelOnboardingCase(supabase, { caseId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not cancel this case: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}

/** HRT-277 decision 2 (section 22 "rehire linked to historical employee") -- the genuinely new terminated -> active employee-lifecycle transition. */
export async function rehireEmployeeAction(
  tenantSlug: string,
  caseId: string,
  masterRecordId: string,
  expectedVersion: number,
  _prevState: OnboardingCaseActionState,
  formData: FormData,
): Promise<OnboardingCaseActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;
  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to rehire an employee." };

  const supabase = await createSupabaseServerClient();
  try {
    await rehireEmployee(supabase, { masterRecordId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not rehire this employee: ${error.message}` };
    throw error;
  }
  revalidatePath(casePath(tenantSlug, caseId));
  return OK;
}
