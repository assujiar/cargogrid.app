"use server";

/**
 * Redemption status/history customer-facing Server Actions (CPL-321,
 * CG-S13-CPL-023). Uses the RLS-scoped `authenticated` client, mirroring
 * every prior capability's own actions.ts convention. The real authority is
 * app.cancel_loyalty_redemption's own dual-authority gate.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { cancelLoyaltyRedemption, LoyaltyRedemptionMutationError } from "../../../../server/mutations/customer-portal-loyalty-redemptions.ts";

export interface CancelLoyaltyRedemptionFormState {
  readonly error: string | null;
}

const INITIAL_STATE: CancelLoyaltyRedemptionFormState = { error: null };

export async function cancelLoyaltyRedemptionAction(
  tenantSlug: string,
  redemptionId: string,
  expectedVersion: number,
  _prevState: CancelLoyaltyRedemptionFormState,
  _formData: FormData,
): Promise<CancelLoyaltyRedemptionFormState> {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's customer portal." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelLoyaltyRedemption(supabase, {
      tenantId: access.tenant.id,
      redemptionId,
      expectedVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyRedemptionMutationError) {
      if (error.code === "stale_version") return { error: "This redemption changed since you last viewed it. Refresh the page and try again." };
      return { error: `Could not cancel this redemption: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/customer-loyalty-redemptions`);
  return INITIAL_STATE;
}
