import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyRedemptions, LoyaltyRedemptionQueryError } from "../../../../server/queries/customer-portal-loyalty-redemptions.ts";
import { listCustomerPortalLoyaltyAccountHoldStatus, LoyaltyExpiryFraudQueryError } from "../../../../server/queries/customer-portal-loyalty-expiry-fraud.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltyRedemptionHistory } from "./customer-loyalty-redemptions-panel.tsx";

/**
 * Redemption status/history (CPL-321, CG-S13-CPL-023). Read-only projection
 * over Loyalty-owned app.loyalty_redemptions (ADR-0024 Part A) plus ONE
 * customer-initiated action, cancellation of a still-pending redemption.
 * Submitting a NEW redemption happens from the reward detail page (app/
 * (tenant)/[tenantSlug]/customer-loyalty-rewards/[rewardId]) -- this screen
 * is status/history only, mirroring CPL-319's own "wallet is a read-plus-
 * action screen, issuance stays admin-side" shape.
 *
 * CPL-322 (Expiry and Fraud Prevention) adds one small, additive block: a
 * generic, customer-safe "account on hold" banner (app.list_customer_
 * portal_loyalty_account_hold_status) -- this is the most directly relevant
 * customer surface, since app.submit_loyalty_redemption's own already-
 * shipped account_on_hold error (CPL-321) is exactly what a held account
 * would hit trying to redeem here. The identical account-level hold is ALSO
 * already visible for free on the unmodified customer-loyalty-tier page
 * (CPL-317, reads the same app.loyalty_account_tier_holds table) -- this
 * checkpoint does not duplicate the banner across every sibling loyalty
 * route, a disclosed scope boundary (ISS-2026-133).
 */
export default async function CustomerLoyaltyRedemptionsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={access.status === "tenant_suspended" ? "This organization's customer portal is currently unavailable." : "You don't have access to this organization's redemptions. Contact your account administrator if you believe this is a mistake."}
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let redemptions: Awaited<ReturnType<typeof listCustomerPortalLoyaltyRedemptions>> = [];
  let holdStatuses: Awaited<ReturnType<typeof listCustomerPortalLoyaltyAccountHoldStatus>> = [];

  try {
    redemptions = await listCustomerPortalLoyaltyRedemptions(supabase, access.tenant.id, access.authUserId, { limit: 100 });
  } catch (error) {
    if (!(error instanceof LoyaltyRedemptionQueryError)) throw error;
    loadFailed = true;
  }

  try {
    holdStatuses = await listCustomerPortalLoyaltyAccountHoldStatus(supabase, access.tenant.id, access.authUserId);
  } catch (error) {
    // A generic hold-status read failure never blocks the primary redemption
    // history view -- it degrades gracefully to "no banner shown," never an
    // ErrorState for a secondary affordance.
    if (!(error instanceof LoyaltyExpiryFraudQueryError)) throw error;
  }
  const heldNotice = holdStatuses.find((status) => status.isOnHold)?.holdNotice ?? null;

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="redemptions" />
        <ErrorState description="Something went wrong loading your redemptions. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="redemptions" />

      {heldNotice ? (
        <p role="status" className="rounded-md bg-warning/10 p-3 text-sm text-warning-strong">
          {heldNotice}
        </p>
      ) : null}

      <div>
        <h1 className="text-xl font-semibold text-text-primary">Redemptions</h1>
        <p className="text-xs text-text-secondary">Rewards you&apos;ve requested, their approval/fulfillment status, and your own redemption history. You can cancel a request that&apos;s still awaiting review.</p>
      </div>

      <CustomerLoyaltyRedemptionHistory tenantSlug={tenantSlug} redemptions={redemptions} />
    </div>
  );
}
