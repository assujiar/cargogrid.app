"use server";

/**
 * Cashback, Discount and Voucher customer-facing Server Actions (CPL-319,
 * CG-S13-CPL-021). `redeemLoyaltyBenefitEntitlementAction` is the FIRST
 * customer-initiated Loyalty write in this repository (migration's own
 * design decision 5) -- gated by `resolveCustomerPortalAccessForRequest`
 * (a real Layer 4 customer-portal-entry check), the actual authority is the
 * underlying RPC's own dual check (staff LYL:Edit OR the entitlement's own
 * owning customer via `app.resolve_customer_account_scope`). Uses the
 * RLS-scoped `authenticated` client, mirroring every prior capability's own
 * actions.ts convention.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { redeemLoyaltyBenefitEntitlement, LoyaltyBenefitsMutationError } from "../../../../server/mutations/customer-portal-loyalty-benefits.ts";

export interface CustomerLoyaltyBenefitsFormState {
  readonly error: string | null;
}

const INITIAL_STATE: CustomerLoyaltyBenefitsFormState = { error: null };

/** Bound to a known, already-listed entitlement's own id + recordVersion (the wallet's own per-row "Redeem" button) -- a real optimistic-concurrency check applies. */
export async function redeemLoyaltyBenefitEntitlementByIdAction(
  tenantSlug: string,
  entitlementId: string,
  expectedVersion: number,
  _prevState: CustomerLoyaltyBenefitsFormState,
  _formData: FormData,
): Promise<CustomerLoyaltyBenefitsFormState> {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's customer portal." };

  const supabase = await createSupabaseServerClient();
  try {
    await redeemLoyaltyBenefitEntitlement(supabase, {
      tenantId: access.tenant.id,
      entitlementIdOrCode: entitlementId,
      expectedVersion,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyBenefitsMutationError) return { error: `Could not redeem this benefit: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/customer-loyalty-benefits`);
  return INITIAL_STATE;
}

/** A bare typed-in voucher code -- no known recordVersion, so expectedVersion is left null (the RPC's own atomic status=issued transition is the concurrency guard). */
export async function redeemLoyaltyBenefitEntitlementByCodeAction(tenantSlug: string, _prevState: CustomerLoyaltyBenefitsFormState, formData: FormData): Promise<CustomerLoyaltyBenefitsFormState> {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's customer portal." };

  const code = String(formData.get("code") ?? "").trim();
  if (code.length === 0) return { error: "A voucher code is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await redeemLoyaltyBenefitEntitlement(supabase, {
      tenantId: access.tenant.id,
      entitlementIdOrCode: code,
      expectedVersion: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyBenefitsMutationError) return { error: "This voucher code could not be redeemed. Double-check the code and try again." };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/customer-loyalty-benefits`);
  return INITIAL_STATE;
}
