"use server";

/**
 * Membership Tier admin Server Actions (CPL-317, CG-S13-CPL-019). Uses the
 * RLS-scoped `authenticated` client -- every RPC below is granted directly
 * to `authenticated` and performs its own LYL:Create/Edit/Configure
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses (e.g. app/(tenant)/[tenantSlug]/admin/loyalty/actions.ts).
 * Gated by resolveTenantAdminAccessForRequest (a coarse tenant_admin
 * portal-entry check) -- the real, per-action LYL:* authority is enforced by
 * each RPC itself, not by this guard.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import {
  createLoyaltyTierDefinition,
  updateLoyaltyTierDefinitionDraft,
  publishLoyaltyTierDefinition,
  recalculateCustomerLoyaltyTier,
  holdLoyaltyAccountTierBenefits,
  releaseLoyaltyAccountTierBenefits,
  LoyaltyTierMutationError,
} from "../../../../../server/mutations/customer-portal-loyalty-tier.ts";

export interface LoyaltyTierAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyTierAdminFormState = { error: null };

function pathFor(tenantSlug: string, programId?: string): string {
  return programId ? `/${tenantSlug}/admin/loyalty-tiers?programId=${programId}` : `/${tenantSlug}/admin/loyalty-tiers`;
}

function parseBenefits(raw: string): { ok: true; value: Record<string, unknown> } | { ok: false; error: string } {
  if (raw.trim().length === 0) return { ok: true, value: {} };
  try {
    const parsed = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return { ok: false, error: "Benefits must be a JSON object, e.g. {\"free_shipping\": true}." };
    }
    return { ok: true, value: parsed as Record<string, unknown> };
  } catch {
    return { ok: false, error: "Benefits must be valid JSON, e.g. {\"free_shipping\": true}." };
  }
}

export async function createLoyaltyTierDefinitionAction(tenantSlug: string, programId: string, _prevState: LoyaltyTierAdminFormState, formData: FormData): Promise<LoyaltyTierAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const tierName = String(formData.get("tierName") ?? "").trim();
  const tierRank = Number(formData.get("tierRank"));
  const thresholdDimension = String(formData.get("thresholdDimension") ?? "").trim();
  const thresholdValue = Number(formData.get("thresholdValue"));
  const reviewPeriodDays = Number(formData.get("reviewPeriodDays") ?? 0);
  const benefitsRaw = String(formData.get("benefits") ?? "");

  if (tierName.length === 0) return { error: "A tier name is required." };
  if (!Number.isFinite(tierRank) || tierRank <= 0) return { error: "Tier rank must be a positive integer." };
  if (thresholdDimension.length === 0) return { error: "A threshold dimension is required." };
  if (!Number.isFinite(thresholdValue) || thresholdValue < 0) return { error: "Threshold value must be a non-negative number." };
  if (!Number.isFinite(reviewPeriodDays) || reviewPeriodDays < 0) return { error: "Review period days must be a non-negative integer." };
  const benefits = parseBenefits(benefitsRaw);
  if (!benefits.ok) return { error: benefits.error };

  const supabase = await createSupabaseServerClient();
  try {
    await createLoyaltyTierDefinition(supabase, {
      tenantId: access.tenant.id,
      programId,
      tierName,
      tierRank,
      thresholdDimension,
      thresholdValue,
      benefits: benefits.value,
      reviewPeriodDays,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyTierMutationError) return { error: `Could not create tier definition: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function updateLoyaltyTierDefinitionDraftAction(
  tenantSlug: string,
  programId: string,
  tierDefinitionId: string,
  expectedVersion: number,
  _prevState: LoyaltyTierAdminFormState,
  formData: FormData,
): Promise<LoyaltyTierAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const tierName = String(formData.get("tierName") ?? "").trim();
  const tierRank = Number(formData.get("tierRank"));
  const thresholdDimension = String(formData.get("thresholdDimension") ?? "").trim();
  const thresholdValue = Number(formData.get("thresholdValue"));
  const reviewPeriodDays = Number(formData.get("reviewPeriodDays") ?? 0);
  const benefitsRaw = String(formData.get("benefits") ?? "");

  if (tierName.length === 0) return { error: "A tier name is required." };
  if (!Number.isFinite(tierRank) || tierRank <= 0) return { error: "Tier rank must be a positive integer." };
  if (thresholdDimension.length === 0) return { error: "A threshold dimension is required." };
  if (!Number.isFinite(thresholdValue) || thresholdValue < 0) return { error: "Threshold value must be a non-negative number." };
  if (!Number.isFinite(reviewPeriodDays) || reviewPeriodDays < 0) return { error: "Review period days must be a non-negative integer." };
  const benefits = parseBenefits(benefitsRaw);
  if (!benefits.ok) return { error: benefits.error };

  const supabase = await createSupabaseServerClient();
  try {
    await updateLoyaltyTierDefinitionDraft(supabase, {
      tenantId: access.tenant.id,
      tierDefinitionId,
      expectedVersion,
      tierName,
      tierRank,
      thresholdDimension,
      thresholdValue,
      benefits: benefits.value,
      reviewPeriodDays,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyTierMutationError) return { error: `Could not save the draft: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function publishLoyaltyTierDefinitionAction(
  tenantSlug: string,
  programId: string,
  tierDefinitionId: string,
  expectedVersion: number,
  _prevState: LoyaltyTierAdminFormState,
  _formData: FormData,
): Promise<LoyaltyTierAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await publishLoyaltyTierDefinition(supabase, { tenantId: access.tenant.id, tierDefinitionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyTierMutationError) return { error: `Could not publish: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function recalculateCustomerLoyaltyTierAction(tenantSlug: string, programId: string, loyaltyAccountId: string, _prevState: LoyaltyTierAdminFormState, _formData: FormData): Promise<LoyaltyTierAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await recalculateCustomerLoyaltyTier(supabase, { tenantId: access.tenant.id, loyaltyAccountId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyTierMutationError) return { error: `Could not recalculate tier: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function holdLoyaltyAccountTierBenefitsAction(tenantSlug: string, programId: string, loyaltyAccountId: string, _prevState: LoyaltyTierAdminFormState, formData: FormData): Promise<LoyaltyTierAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) return { error: "A reason is required to hold this account's tier benefits." };

  const supabase = await createSupabaseServerClient();
  try {
    await holdLoyaltyAccountTierBenefits(supabase, { tenantId: access.tenant.id, loyaltyAccountId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyTierMutationError) return { error: `Could not hold this account's benefits: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function releaseLoyaltyAccountTierBenefitsAction(tenantSlug: string, programId: string, loyaltyAccountId: string, _prevState: LoyaltyTierAdminFormState, _formData: FormData): Promise<LoyaltyTierAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await releaseLoyaltyAccountTierBenefits(supabase, { tenantId: access.tenant.id, loyaltyAccountId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyTierMutationError) return { error: `Could not release this account's benefits hold: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}
