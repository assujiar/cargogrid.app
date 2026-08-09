"use server";

/**
 * Checklist template authoring Server Actions (HRT-277, CG-S12-HRT-005, section
 * 20 "versioned onboarding/offboarding workflow"). Mirrors
 * app/(tenant)/[tenantSlug]/hris/positions/actions.ts's own shape.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { requireOnboardingAccess } from "../actions.ts";
import {
  createOnboardingChecklistTemplate,
  createOnboardingChecklistTemplateVersion,
  addOnboardingChecklistTemplateTask,
  addOnboardingChecklistTemplateTaskDependency,
  publishOnboardingChecklistTemplateVersion,
  OnboardingMutationError,
} from "../../../../../../server/mutations/onboarding.ts";
import type { CaseType, TaskType, HandoffCategory, OwnerType } from "../../../../../../server/contracts/onboarding/onboarding.ts";

export interface TemplateActionState {
  readonly error: string | null;
}

const OK: TemplateActionState = { error: null };
const NO_ACCESS: TemplateActionState = { error: "You don't have access to this organization's HRIS workspace." };

function listPath(tenantSlug: string): string {
  return `/${tenantSlug}/hris/onboarding/templates`;
}

export async function createTemplateAction(tenantSlug: string, _prevState: TemplateActionState, formData: FormData): Promise<TemplateActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const caseType = String(formData.get("caseType") ?? "onboarding") as CaseType;

  const supabase = await createSupabaseServerClient();
  try {
    await createOnboardingChecklistTemplate(supabase, { tenantId: access.tenant.id, code, name, caseType, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not create this template: ${error.message}` };
    throw error;
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}

/** Idempotent -- returns the existing draft if one is already open, then redirects to it. */
export async function openDraftVersionAction(tenantSlug: string, templateId: string, _prevState: TemplateActionState, _formData: FormData): Promise<TemplateActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  let versionId: string;
  try {
    const version = await createOnboardingChecklistTemplateVersion(supabase, { templateId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    versionId = version.id;
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not open a draft version: ${error.message}` };
    throw error;
  }
  redirect(`${listPath(tenantSlug)}/${templateId}/${versionId}`);
}

export async function addTemplateTaskAction(tenantSlug: string, templateVersionId: string, _prevState: TemplateActionState, formData: FormData): Promise<TemplateActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const taskKey = String(formData.get("taskKey") ?? "").trim();
  const title = String(formData.get("title") ?? "").trim();
  const taskType = String(formData.get("taskType") ?? "generic") as TaskType;
  const handoffCategoryRaw = String(formData.get("handoffCategory") ?? "").trim();
  const handoffCategory = (handoffCategoryRaw || null) as HandoffCategory | null;
  const ownerType = String(formData.get("ownerType") ?? "hr") as OwnerType;
  const isMandatory = formData.get("isMandatory") === "on";
  const slaDays = Number(String(formData.get("slaDays") ?? "3")) || 3;
  const sortOrder = Number(String(formData.get("sortOrder") ?? "0")) || 0;

  const supabase = await createSupabaseServerClient();
  try {
    await addOnboardingChecklistTemplateTask(supabase, {
      templateVersionId,
      taskKey,
      title,
      description: null,
      taskType,
      handoffCategory,
      ownerType,
      isMandatory,
      slaDays,
      sortOrder,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not add this task: ${error.message}` };
    throw error;
  }
  return OK;
}

export async function addTemplateTaskDependencyAction(tenantSlug: string, templateVersionId: string, _prevState: TemplateActionState, formData: FormData): Promise<TemplateActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const taskKey = String(formData.get("taskKey") ?? "").trim();
  const dependsOnTaskKey = String(formData.get("dependsOnTaskKey") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await addOnboardingChecklistTemplateTaskDependency(supabase, { templateVersionId, taskKey, dependsOnTaskKey, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not add this dependency: ${error.message}` };
    throw error;
  }
  return OK;
}

export async function publishTemplateVersionAction(tenantSlug: string, templateVersionId: string, expectedVersion: number, _prevState: TemplateActionState, _formData: FormData): Promise<TemplateActionState> {
  const access = await requireOnboardingAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await publishOnboardingChecklistTemplateVersion(supabase, { templateVersionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof OnboardingMutationError) return { error: `Could not publish this version: ${error.message}` };
    throw error;
  }
  revalidatePath(listPath(tenantSlug));
  return OK;
}
