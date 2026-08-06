"use server";

/**
 * Vendor Assessment Template Server Actions (PRC-252, CG-S11-PRC-003) --
 * Procurement/compliance admin only in practice (PRC:Create/Edit/Approve gated by
 * the RPCs themselves). Mirrors app/(tenant)/[tenantSlug]/procurement/assessments/
 * actions.ts's own shape.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createVendorAssessmentTemplateDraft,
  updateVendorAssessmentTemplateDraft,
  addVendorAssessmentTemplateCriterion,
  updateVendorAssessmentTemplateCriterion,
  removeVendorAssessmentTemplateCriterion,
  publishVendorAssessmentTemplate,
  archiveVendorAssessmentTemplate,
  VendorAssessmentMutationError,
} from "../../../../../../server/mutations/vendor-assessment.ts";
import type { VendorAssessmentType, VendorAssessmentPurposeTag } from "../../../../../../server/contracts/vendor-assessment/vendor-assessment.ts";

export interface TemplateActionState {
  readonly error: string | null;
}

const OK: TemplateActionState = { error: null };
const NO_ACCESS: TemplateActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

type Mutation = (client: Awaited<ReturnType<typeof createSupabaseServerClient>>, input: never) => Promise<unknown>;

async function runAction(tenantSlug: string, templateVersionId: string | null, mutation: Mutation, input: Record<string, unknown>, failureVerb: string): Promise<TemplateActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await mutation(supabase, { ...input, actorAuthUserId: access.authUserId, actorLabel: access.authUserId } as never);
  } catch (error) {
    if (error instanceof VendorAssessmentMutationError) return { error: `Could not ${failureVerb}: ${error.message}` };
    throw error;
  }

  if (templateVersionId) revalidatePath(`/${tenantSlug}/procurement/assessments/templates/${templateVersionId}`);
  revalidatePath(`/${tenantSlug}/procurement/assessments/templates`);
  return OK;
}

export async function createVendorAssessmentTemplateDraftAction(tenantSlug: string, _prevState: TemplateActionState, formData: FormData): Promise<TemplateActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const vendorCategory = String(formData.get("vendorCategory") ?? "").trim() || null;
  const assessmentType = String(formData.get("assessmentType") ?? "") as VendorAssessmentType;
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const validityPeriodDays = Number(String(formData.get("validityPeriodDays") ?? "180"));
  const passThreshold = Number(String(formData.get("passThreshold") ?? "80"));
  const conditionalThreshold = Number(String(formData.get("conditionalThreshold") ?? "60"));

  return runAction(
    tenantSlug,
    null,
    createVendorAssessmentTemplateDraft as Mutation,
    { tenantId: access.tenant.id, vendorCategory, assessmentType, name, description, validityPeriodDays, passThreshold, conditionalThreshold, weightTotalRequired: 100, idempotencyKey: null },
    "create this template draft",
  );
}

export async function updateVendorAssessmentTemplateDraftAction(tenantSlug: string, templateVersionId: string, expectedVersion: number, _prevState: TemplateActionState, formData: FormData) {
  const vendorCategory = String(formData.get("vendorCategory") ?? "").trim() || null;
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const validityPeriodDays = Number(String(formData.get("validityPeriodDays") ?? "180"));
  const passThreshold = Number(String(formData.get("passThreshold") ?? "80"));
  const conditionalThreshold = Number(String(formData.get("conditionalThreshold") ?? "60"));
  return runAction(
    tenantSlug,
    templateVersionId,
    updateVendorAssessmentTemplateDraft as Mutation,
    { templateVersionId, expectedVersion, vendorCategory, name, description, validityPeriodDays, passThreshold, conditionalThreshold, weightTotalRequired: 100 },
    "update this template draft",
  );
}

export async function addVendorAssessmentTemplateCriterionAction(tenantSlug: string, templateVersionId: string, _prevState: TemplateActionState, formData: FormData) {
  const label = String(formData.get("label") ?? "").trim();
  const purposeTag = String(formData.get("purposeTag") ?? "operational") as VendorAssessmentPurposeTag;
  const weight = Number(String(formData.get("weight") ?? ""));
  const scoringGuidance = String(formData.get("scoringGuidance") ?? "").trim() || null;
  return runAction(tenantSlug, templateVersionId, addVendorAssessmentTemplateCriterion as Mutation, { templateVersionId, label, purposeTag, weight, scoringGuidance, displayOrder: 0 }, "add this criterion");
}

export async function removeVendorAssessmentTemplateCriterionAction(tenantSlug: string, templateVersionId: string, criterionId: string, expectedVersion: number, _prevState: TemplateActionState, _formData: FormData) {
  return runAction(tenantSlug, templateVersionId, removeVendorAssessmentTemplateCriterion as Mutation, { criterionId, expectedVersion }, "remove this criterion");
}

export async function publishVendorAssessmentTemplateAction(tenantSlug: string, templateVersionId: string, expectedVersion: number, _prevState: TemplateActionState, formData: FormData) {
  const supersedesVersionId = String(formData.get("supersedesVersionId") ?? "").trim() || null;
  return runAction(tenantSlug, templateVersionId, publishVendorAssessmentTemplate as Mutation, { templateVersionId, expectedVersion, supersedesVersionId }, "publish this template");
}

export async function archiveVendorAssessmentTemplateAction(tenantSlug: string, templateVersionId: string, expectedVersion: number, _prevState: TemplateActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  return runAction(tenantSlug, templateVersionId, archiveVendorAssessmentTemplate as Mutation, { templateVersionId, expectedVersion, reason }, "archive this template");
}
