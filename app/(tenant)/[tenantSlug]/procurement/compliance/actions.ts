"use server";

/**
 * Vendor Compliance Requirement + tenant-wide recalculation Server Actions (PRC-253,
 * CG-S11-PRC-004). Mirrors app/(tenant)/[tenantSlug]/procurement/assessments/
 * templates/actions.ts's own shape: resolve portal access, call the typed mutation
 * wrapper, translate a known mutation error into a plain-language message, revalidate
 * the affected path(s). Authorization is enforced server-side by the RPCs themselves
 * (evaluate_permission) -- this file never hides an action from an unauthorized
 * viewer client-side only.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createVendorComplianceRequirementDraft,
  updateVendorComplianceRequirementDraft,
  publishVendorComplianceRequirement,
  archiveVendorComplianceRequirement,
  recalculateTenantVendorComplianceStatus,
  VendorComplianceMutationError,
} from "../../../../../server/mutations/vendor-compliance.ts";
import type { VendorComplianceBlockingEffect } from "../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";

export interface ComplianceActionState {
  readonly error: string | null;
}

const OK: ComplianceActionState = { error: null };
const NO_ACCESS: ComplianceActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

type Mutation = (client: Awaited<ReturnType<typeof createSupabaseServerClient>>, input: never) => Promise<unknown>;

async function runAction(tenantSlug: string, requirementVersionId: string | null, mutation: Mutation, input: Record<string, unknown>, failureVerb: string): Promise<ComplianceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await mutation(supabase, { ...input, actorAuthUserId: access.authUserId, actorLabel: access.authUserId } as never);
  } catch (error) {
    if (error instanceof VendorComplianceMutationError) return { error: `Could not ${failureVerb}: ${error.message}` };
    throw error;
  }

  if (requirementVersionId) revalidatePath(`/${tenantSlug}/procurement/compliance/requirements/${requirementVersionId}`);
  revalidatePath(`/${tenantSlug}/procurement/compliance/requirements`);
  revalidatePath(`/${tenantSlug}/procurement/compliance`);
  return OK;
}

function parseReminderOffsets(raw: string): number[] | null {
  const trimmed = raw.trim();
  if (trimmed.length === 0) return null;
  const parts = trimmed
    .split(",")
    .map((p) => p.trim())
    .filter((p) => p.length > 0)
    .map(Number);
  return parts.every((n) => Number.isFinite(n)) ? parts : null;
}

export async function createVendorComplianceRequirementDraftAction(tenantSlug: string, _prevState: ComplianceActionState, formData: FormData): Promise<ComplianceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const vendorCategory = String(formData.get("vendorCategory") ?? "").trim() || null;
  const serviceType = String(formData.get("serviceType") ?? "").trim() || null;
  const documentTypeCode = String(formData.get("documentTypeCode") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const blockingEffect = String(formData.get("blockingEffect") ?? "blocking") as VendorComplianceBlockingEffect;
  const requiresExpiry = formData.get("requiresExpiry") === "on";
  const reminderOffsets = parseReminderOffsets(String(formData.get("reminderOffsets") ?? ""));

  return runAction(
    tenantSlug,
    null,
    createVendorComplianceRequirementDraft as Mutation,
    { tenantId: access.tenant.id, vendorCategory, serviceType, documentTypeCode, name, description, blockingEffect, requiresExpiry, reminderOffsets, idempotencyKey: null },
    "create this requirement draft",
  );
}

export async function updateVendorComplianceRequirementDraftAction(tenantSlug: string, requirementVersionId: string, expectedVersion: number, _prevState: ComplianceActionState, formData: FormData) {
  const vendorCategory = String(formData.get("vendorCategory") ?? "").trim() || null;
  const serviceType = String(formData.get("serviceType") ?? "").trim() || null;
  const documentTypeCode = String(formData.get("documentTypeCode") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim() || null;
  const blockingEffect = String(formData.get("blockingEffect") ?? "blocking") as VendorComplianceBlockingEffect;
  const requiresExpiry = formData.get("requiresExpiry") === "on";
  const reminderOffsets = parseReminderOffsets(String(formData.get("reminderOffsets") ?? ""));

  return runAction(
    tenantSlug,
    requirementVersionId,
    updateVendorComplianceRequirementDraft as Mutation,
    { requirementVersionId, expectedVersion, vendorCategory, serviceType, documentTypeCode, name, description, blockingEffect, requiresExpiry, reminderOffsets },
    "update this requirement draft",
  );
}

export async function publishVendorComplianceRequirementAction(tenantSlug: string, requirementVersionId: string, expectedVersion: number, _prevState: ComplianceActionState, formData: FormData) {
  const supersedesVersionId = String(formData.get("supersedesVersionId") ?? "").trim() || null;
  return runAction(tenantSlug, requirementVersionId, publishVendorComplianceRequirement as Mutation, { requirementVersionId, expectedVersion, supersedesVersionId }, "publish this requirement");
}

export async function archiveVendorComplianceRequirementAction(tenantSlug: string, requirementVersionId: string, expectedVersion: number, _prevState: ComplianceActionState, formData: FormData) {
  const reason = String(formData.get("reason") ?? "").trim();
  return runAction(tenantSlug, requirementVersionId, archiveVendorComplianceRequirement as Mutation, { requirementVersionId, expectedVersion, reason }, "archive this requirement");
}

/** Bulk, PRC:Override-gated recalculation sweep -- the operator tool for "I just changed requirements, refresh every vendor's own hold now" (design note 8: real, bounded, not auto-scheduled -- ISS-2026-015). */
export async function recalculateTenantVendorComplianceStatusAction(tenantSlug: string, _prevState: ComplianceActionState, _formData: FormData): Promise<ComplianceActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await recalculateTenantVendorComplianceStatus(supabase, { tenantId: access.tenant.id, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorComplianceMutationError) return { error: `Could not recalculate tenant compliance status: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/compliance`);
  return OK;
}
