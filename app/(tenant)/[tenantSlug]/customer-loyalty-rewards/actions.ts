"use server";

/**
 * Reward Catalogue customer-facing checkout Server Action (CPL-321,
 * CG-S13-CPL-023) -- shared by the catalogue detail page's own "Redeem"
 * form. Uses the RLS-scoped `authenticated` client, mirroring every prior
 * capability's own actions.ts convention -- the real authority is app.
 * submit_loyalty_redemption's own dual-authority gate (customer_user own
 * account scope OR staff LYL:Edit), never this coarse portal-entry guard
 * alone.
 *
 * `p_idempotency_key` is generated here, server-side, via `crypto.
 * randomUUID()` on every call -- never a client-side Date.now()-based
 * derivation. A genuine double-click is already prevented at the UI layer
 * (the Redeem button disables itself while `pending`, useActionState);
 * this key protects the database layer against any OTHER accidental
 * duplicate RPC call for the SAME logical redemption request -- mirrors
 * app/(tenant)/[tenantSlug]/admin/loyalty-benefits/actions.ts's own
 * identical, already-accepted precedent (per-call randomUUID(), not a
 * render-time key threaded through a hidden field) rather than CPL-314's
 * own render-time-key precedent -- this is a single, explicit-intent button
 * click, not a multi-field form a user might legitimately resubmit.
 */

import { randomUUID } from "node:crypto";
import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { submitLoyaltyRedemption, LoyaltyRedemptionMutationError } from "../../../../server/mutations/customer-portal-loyalty-redemptions.ts";

export interface SubmitLoyaltyRedemptionFormState {
  readonly error: string | null;
  readonly redemptionId: string | null;
  readonly status: string | null;
}

const INITIAL_STATE: SubmitLoyaltyRedemptionFormState = { error: null, redemptionId: null, status: null };

export async function submitLoyaltyRedemptionAction(
  tenantSlug: string,
  loyaltyAccountId: string,
  rewardId: string,
  _prevState: SubmitLoyaltyRedemptionFormState,
  _formData: FormData,
): Promise<SubmitLoyaltyRedemptionFormState> {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { ...INITIAL_STATE, error: "You don't have access to this organization's customer portal." };

  const supabase = await createSupabaseServerClient();
  try {
    const redemption = await submitLoyaltyRedemption(supabase, {
      tenantId: access.tenant.id,
      loyaltyAccountId,
      rewardId,
      idempotencyKey: randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });

    revalidatePath(`/${tenantSlug}/customer-loyalty-rewards/${rewardId}`);
    revalidatePath(`/${tenantSlug}/customer-loyalty-rewards`);
    revalidatePath(`/${tenantSlug}/customer-loyalty-redemptions`);
    return { error: null, redemptionId: redemption.id, status: redemption.status };
  } catch (error) {
    if (error instanceof LoyaltyRedemptionMutationError) return { ...INITIAL_STATE, error: `Could not redeem this reward: ${error.message}` };
    throw error;
  }
}
