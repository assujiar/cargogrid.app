"use server";

/**
 * Onboarding/offboarding case Server Actions -- top-level (case list/start).
 * Mirrors app/(tenant)/[tenantSlug]/hris/employees/actions.ts's own shape.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import { startOnboardingCase, OnboardingMutationError } from "../../../../../server/mutations/onboarding.ts";
import type { CaseType, SourceType } from "../../../../../server/contracts/onboarding/onboarding.ts";

export interface OnboardingActionState {
  readonly error: string | null;
}

const OK: OnboardingActionState = { error: null };
const NO_ACCESS: OnboardingActionState = { error: "You don't have access to this organization's HRIS workspace." };

export async function requireOnboardingAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/hris/onboarding`;
}

export async function startOnboardingCaseAction(tenantSlug: string, _prevState: OnboardingActionState, formData: FormData): Promise<OnboardingActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const caseType = String(formData.get("caseType") ?? "onboarding") as CaseType;
  const sourceType = String(formData.get("sourceType") ?? "direct_hire") as SourceType;
  const sourceJobOfferId = String(formData.get("sourceJobOfferId") ?? "").trim() || null;
  const employeeMasterRecordId = String(formData.get("employeeMasterRecordId") ?? "").trim() || null;
  const fullName = String(formData.get("fullName") ?? "").trim() || null;
  const employmentType = String(formData.get("employmentType") ?? "").trim() || null;
  const workEmail = String(formData.get("workEmail") ?? "").trim() || null;
  const personalEmail = String(formData.get("personalEmail") ?? "").trim() || null;
  const companyOrgUnitId = String(formData.get("companyOrgUnitId") ?? "").trim() || null;
  const branchOrgUnitId = String(formData.get("branchOrgUnitId") ?? "").trim() || null;
  const departmentOrgUnitId = String(formData.get("departmentOrgUnitId") ?? "").trim() || null;
  const effectiveDate = String(formData.get("effectiveDate") ?? "").trim() || null;
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  let caseId: string;
  try {
    const result = await startOnboardingCase(supabase, {
      tenantId: access.tenant.id,
      caseType,
      sourceType,
      sourceJobOfferId,
      employeeMasterRecordId,
      checklistTemplateVersionId: null,
      effectiveDate,
      fullName,
      employmentType,
      workEmail,
      personalEmail,
      personalPhone: null,
      nationalIdNumber: null,
      dateOfBirth: null,
      gender: null,
      companyOrgUnitId,
      branchOrgUnitId,
      departmentOrgUnitId,
      positionTitle: null,
      managerEmployeeId: null,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    caseId = result.id;
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not start this case: ${error.message}` };
    throw error;
  }

  revalidatePath(listPath(tenantSlug));
  redirect(`${listPath(tenantSlug)}/${caseId}`);
}
