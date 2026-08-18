"use server";

/**
 * Reward Catalogue admin Server Actions (CPL-320, CG-S13-CPL-022). Uses the
 * RLS-scoped `authenticated` client -- every RPC below is granted directly
 * to `authenticated` and performs its own LYL:Create/Edit/Configure
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses (e.g. app/(tenant)/[tenantSlug]/admin/loyalty-tiers/
 * actions.ts). Gated by resolveTenantAdminAccessForRequest (a coarse
 * tenant_admin portal-entry check) -- the real, per-action LYL:* authority
 * is enforced by each RPC itself, not by this guard.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createLoyaltyRewardDraft, updateLoyaltyRewardDraft, publishLoyaltyReward, pauseLoyaltyReward, resumeLoyaltyReward, archiveLoyaltyReward, LoyaltyRewardMutationError } from "../../../../../server/mutations/customer-portal-loyalty-rewards.ts";
import type { LoyaltyRewardType } from "../../../../../server/contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";

export interface LoyaltyRewardAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyRewardAdminFormState = { error: null };

function pathFor(tenantSlug: string, programId?: string): string {
  return programId ? `/${tenantSlug}/admin/loyalty-rewards?programId=${programId}` : `/${tenantSlug}/admin/loyalty-rewards`;
}

function readNullableText(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length === 0 ? null : raw;
}

function readNullableNumber(formData: FormData, key: string): number | null {
  const raw = String(formData.get(key) ?? "").trim();
  if (raw.length === 0) return null;
  const parsed = Number(raw);
  return Number.isFinite(parsed) ? parsed : NaN;
}

function readDraftFields(formData: FormData): { rewardName: string; rewardType: string; description: string | null; termsText: string | null; minTierId: string | null; minPointsRequired: number | null; totalStock: number | null; internalCost: number | null; vendorRef: string | null; fileId: string | null } | { error: string } {
  const rewardName = String(formData.get("rewardName") ?? "").trim();
  const rewardType = String(formData.get("rewardType") ?? "").trim();
  if (rewardName.length === 0) return { error: "A reward name is required." };
  if (rewardType.length === 0) return { error: "A reward type is required." };

  const minPointsRequired = readNullableNumber(formData, "minPointsRequired");
  if (Number.isNaN(minPointsRequired)) return { error: "Minimum points required must be a number." };
  const totalStock = readNullableNumber(formData, "totalStock");
  if (Number.isNaN(totalStock)) return { error: "Total stock must be a whole number." };
  const internalCost = readNullableNumber(formData, "internalCost");
  if (Number.isNaN(internalCost)) return { error: "Internal cost must be a number." };

  return {
    rewardName,
    rewardType,
    description: readNullableText(formData, "description"),
    termsText: readNullableText(formData, "termsText"),
    minTierId: readNullableText(formData, "minTierId"),
    minPointsRequired,
    totalStock: totalStock === null ? null : Math.trunc(totalStock),
    internalCost,
    vendorRef: readNullableText(formData, "vendorRef"),
    fileId: readNullableText(formData, "fileId"),
  };
}

export async function createLoyaltyRewardDraftAction(tenantSlug: string, programId: string, _prevState: LoyaltyRewardAdminFormState, formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const fields = readDraftFields(formData);
  if ("error" in fields) return fields;

  const supabase = await createSupabaseServerClient();
  try {
    await createLoyaltyRewardDraft(supabase, {
      tenantId: access.tenant.id,
      programId,
      rewardName: fields.rewardName,
      rewardType: fields.rewardType as LoyaltyRewardType,
      description: fields.description,
      termsText: fields.termsText,
      minTierId: fields.minTierId,
      minPointsRequired: fields.minPointsRequired,
      totalStock: fields.totalStock,
      internalCost: fields.internalCost,
      vendorRef: fields.vendorRef,
      fileId: fields.fileId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not create the reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function updateLoyaltyRewardDraftAction(
  tenantSlug: string,
  programId: string,
  rewardId: string,
  expectedVersion: number,
  _prevState: LoyaltyRewardAdminFormState,
  formData: FormData,
): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const fields = readDraftFields(formData);
  if ("error" in fields) return fields;

  const supabase = await createSupabaseServerClient();
  try {
    await updateLoyaltyRewardDraft(supabase, {
      tenantId: access.tenant.id,
      rewardId,
      expectedVersion,
      rewardName: fields.rewardName,
      rewardType: fields.rewardType as LoyaltyRewardType,
      description: fields.description,
      termsText: fields.termsText,
      minTierId: fields.minTierId,
      minPointsRequired: fields.minPointsRequired,
      totalStock: fields.totalStock,
      internalCost: fields.internalCost,
      vendorRef: fields.vendorRef,
      fileId: fields.fileId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not save the draft: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function publishLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, _formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await publishLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not publish: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function pauseLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await pauseLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, reason: readNullableText(formData, "reason"), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not pause this reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function resumeLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, _formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await resumeLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not resume this reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}

export async function archiveLoyaltyRewardAction(tenantSlug: string, programId: string, rewardId: string, expectedVersion: number, _prevState: LoyaltyRewardAdminFormState, formData: FormData): Promise<LoyaltyRewardAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await archiveLoyaltyReward(supabase, { tenantId: access.tenant.id, rewardId, expectedVersion, reason: readNullableText(formData, "reason"), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRewardMutationError) return { error: `Could not archive this reward: ${error.message}` };
    throw error;
  }

  revalidatePath(pathFor(tenantSlug, programId));
  return INITIAL_STATE;
}
