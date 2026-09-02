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
import { previewOnboardingCaseStart, exportOnboardingCases, OnboardingQueryError } from "../../../../../server/queries/onboarding.ts";
import { buildOnboardingExport } from "../../../../../lib/onboarding/onboarding-export-action.ts";
import { ONBOARDING_EXPORT_INITIAL_STATE, type OnboardingExportActionState } from "../../../../../components/domain/onboarding-export-form.tsx";
import type { CaseType, SourceType, CaseStatus, OnboardingCasePreview } from "../../../../../server/contracts/onboarding/onboarding.ts";

export interface OnboardingActionState {
  readonly error: string | null;
}

const OK: OnboardingActionState = { error: null };
const NO_ACCESS: OnboardingActionState = { error: "You don't have access to this organization's HRIS workspace." };

export interface OnboardingPreviewActionState {
  readonly error: string | null;
  readonly preview: OnboardingCasePreview | null;
}

const PREVIEW_NO_ACCESS: OnboardingPreviewActionState = { error: "You don't have access to this organization's HRIS workspace.", preview: null };

export async function requireOnboardingAccess(tenantSlug: string) {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/hris/onboarding`;
}

/** ISS-2026-070 item 3: preview a case before starting it -- app.preview_onboarding_case_start had no UI caller. Never mutates anything. */
export async function previewOnboardingCaseStartAction(tenantSlug: string, _prevState: OnboardingPreviewActionState, formData: FormData): Promise<OnboardingPreviewActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return PREVIEW_NO_ACCESS;

  const caseType = String(formData.get("caseType") ?? "onboarding") as CaseType;
  const sourceType = String(formData.get("sourceType") ?? "direct_hire") as SourceType;
  const sourceJobOfferId = String(formData.get("sourceJobOfferId") ?? "").trim() || null;
  const employeeMasterRecordId = String(formData.get("employeeMasterRecordId") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  try {
    const preview = await previewOnboardingCaseStart(supabase, {
      tenantId: access.tenant.id,
      caseType,
      sourceType,
      sourceJobOfferId,
      employeeMasterRecordId,
      actorAuthUserId: access.authUserId,
    });
    return { error: null, preview };
  } catch (error) {
    if (error instanceof OnboardingQueryError) return { error: `Could not compute a preview: ${error.message}`, preview: null };
    throw error;
  }
}

/** ISS-2026-070 item 3: app.export_onboarding_cases had no UI caller. app.export_onboarding_cases itself only accepts a status filter (no case-type filter) -- respects the list page's own status filter, the same one the underlying RPC understands. */
export async function exportOnboardingCasesAction(
  tenantSlug: string,
  statusFilter: CaseStatus | null,
  _prevState: OnboardingExportActionState,
  _formData: FormData,
): Promise<OnboardingExportActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return { ...ONBOARDING_EXPORT_INITIAL_STATE, error: "You don't have access to this organization's HRIS workspace." };

  const supabase = await createSupabaseServerClient();
  return buildOnboardingExport({
    filenameStem: `onboarding-cases${statusFilter ? `-${statusFilter}` : ""}`,
    header: ["Case type", "Source type", "Employee", "Status", "Effective date", "Initiated at"],
    fetchRows: () => exportOnboardingCases(supabase, access.tenant.id, access.authUserId, { statusFilter, limit: 500 }),
    toCells: (row) => [row.caseType, row.sourceType, row.employeeFullName ?? "", row.status, row.effectiveDate ?? "", row.initiatedAt],
  });
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
