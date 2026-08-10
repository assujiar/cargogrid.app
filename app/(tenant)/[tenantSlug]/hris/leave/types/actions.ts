"use server";

/**
 * Leave type / policy version authoring Server Actions (HRT-280,
 * CG-S12-HRT-008). Create is HRS:Edit; publish is HRS:Approve (decision 12).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import { createLeaveType, publishLeaveType, createLeaveTypePolicyVersion, publishLeaveTypePolicyVersion, LeaveMutationError } from "../../../../../../server/mutations/leave.ts";
import type { LeaveCategory, EvidenceClassification, AccrualFrequency } from "../../../../../../server/contracts/leave/leave.ts";

export interface LeaveTypeActionState {
  readonly error: string | null;
}

const OK: LeaveTypeActionState = { error: null };
const NO_ACCESS: LeaveTypeActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/leave/types`;
}

export async function createLeaveTypeAction(tenantSlug: string, _prevState: LeaveTypeActionState, formData: FormData): Promise<LeaveTypeActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const category = String(formData.get("category") ?? "leave") as LeaveCategory;
  const requiresBalance = formData.get("requiresBalance") === "on";
  const requiresEvidence = formData.get("requiresEvidence") === "on";
  const evidenceClassification = String(formData.get("evidenceClassification") ?? "none") as EvidenceClassification;
  if (!code || !name) return { error: "Code and name are both required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createLeaveType(supabase, { tenantId: access.tenant.id, code, name, category, requiresBalance, requiresEvidence, evidenceClassification, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not create this leave type: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function publishLeaveTypeAction(tenantSlug: string, leaveTypeId: string, expectedVersion: number, _prevState: LeaveTypeActionState, _formData: FormData): Promise<LeaveTypeActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishLeaveType(supabase, { leaveTypeId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not publish this leave type: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createAndPublishPolicyVersionAction(tenantSlug: string, leaveTypeId: string, _prevState: LeaveTypeActionState, formData: FormData): Promise<LeaveTypeActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const effectiveFrom = String(formData.get("effectiveFrom") ?? "").trim();
  const accrualFrequency = String(formData.get("accrualFrequency") ?? "none") as AccrualFrequency;
  const accrualAmountPerPeriod = Number(String(formData.get("accrualAmountPerPeriod") ?? "0"));
  const carryForwardMaxUnits = Number(String(formData.get("carryForwardMaxUnits") ?? "0"));
  const minNoticeDays = Number(String(formData.get("minNoticeDays") ?? "0"));
  const eligibilityMinTenureDays = Number(String(formData.get("eligibilityMinTenureDays") ?? "0"));
  const negativeBalanceAllowed = formData.get("negativeBalanceAllowed") === "on";
  if (!effectiveFrom) return { error: "An effective-from date is required." };

  const supabase = await createSupabaseServerClient();
  try {
    const version = await createLeaveTypePolicyVersion(supabase, {
      leaveTypeId,
      orgUnitId: null,
      effectiveFrom,
      accrualFrequency,
      accrualAmountPerPeriod,
      accrualMaxBalance: null,
      carryForwardMaxUnits,
      minNoticeDays,
      maxConsecutiveUnits: null,
      eligibilityMinTenureDays,
      negativeBalanceAllowed,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    const versionRow = version as { id: string; record_version: number };
    await publishLeaveTypePolicyVersion(supabase, { versionId: versionRow.id, expectedVersion: versionRow.record_version, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LeaveMutationError) return { error: `Could not create and publish this policy version: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
