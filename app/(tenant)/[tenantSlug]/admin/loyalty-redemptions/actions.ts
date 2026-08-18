"use server";

/**
 * Redemption Approval and Fulfillment admin Server Actions (CPL-321,
 * CG-S13-CPL-023). Uses the RLS-scoped `authenticated` client -- every RPC
 * below is granted directly to `authenticated` and performs its own
 * LYL:Configure/Edit authority check in-body, the same convention every
 * prior capability's own actions.ts uses. Gated by
 * resolveTenantAdminAccessForRequest (a coarse tenant_admin portal-entry
 * check) -- the real, per-action LYL:* authority is enforced by each RPC
 * itself, not by this guard.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { decideLoyaltyRedemption, markLoyaltyRedemptionFulfilled, markLoyaltyRedemptionFulfillmentFailed, LoyaltyRedemptionMutationError } from "../../../../../server/mutations/customer-portal-loyalty-redemptions.ts";

export interface LoyaltyRedemptionAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyRedemptionAdminFormState = { error: null };

function readNullableText(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length === 0 ? null : raw;
}

export async function approveLoyaltyRedemptionAction(tenantSlug: string, redemptionId: string, expectedVersion: number, _prevState: LoyaltyRedemptionAdminFormState, formData: FormData): Promise<LoyaltyRedemptionAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideLoyaltyRedemption(supabase, {
      tenantId: access.tenant.id,
      redemptionId,
      expectedVersion,
      decision: "approve",
      decisionReason: readNullableText(formData, "reason"),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRedemptionMutationError) return { error: `Could not approve this redemption: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-redemptions`);
  return INITIAL_STATE;
}

export async function rejectLoyaltyRedemptionAction(tenantSlug: string, redemptionId: string, expectedVersion: number, _prevState: LoyaltyRedemptionAdminFormState, formData: FormData): Promise<LoyaltyRedemptionAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = readNullableText(formData, "reason");
  if (!reason) return { error: "A reason is required to reject a redemption." };

  const supabase = await createSupabaseServerClient();
  try {
    await decideLoyaltyRedemption(supabase, {
      tenantId: access.tenant.id,
      redemptionId,
      expectedVersion,
      decision: "reject",
      decisionReason: reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRedemptionMutationError) return { error: `Could not reject this redemption: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-redemptions`);
  return INITIAL_STATE;
}

export async function markLoyaltyRedemptionFulfilledAction(tenantSlug: string, redemptionId: string, expectedVersion: number, _prevState: LoyaltyRedemptionAdminFormState, _formData: FormData): Promise<LoyaltyRedemptionAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await markLoyaltyRedemptionFulfilled(supabase, { tenantId: access.tenant.id, redemptionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRedemptionMutationError) return { error: `Could not mark this redemption fulfilled: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-redemptions`);
  return INITIAL_STATE;
}

export async function markLoyaltyRedemptionFulfillmentFailedAction(
  tenantSlug: string,
  redemptionId: string,
  expectedVersion: number,
  _prevState: LoyaltyRedemptionAdminFormState,
  formData: FormData,
): Promise<LoyaltyRedemptionAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const reason = readNullableText(formData, "reason");
  if (!reason) return { error: "A reason is required to mark a fulfillment failed." };

  const supabase = await createSupabaseServerClient();
  try {
    await markLoyaltyRedemptionFulfillmentFailed(supabase, { tenantId: access.tenant.id, redemptionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof LoyaltyRedemptionMutationError) return { error: `Could not mark this redemption failed: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-redemptions`);
  return INITIAL_STATE;
}
