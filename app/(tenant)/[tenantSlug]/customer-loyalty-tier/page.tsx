import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyTierCards, LoyaltyTierQueryError } from "../../../../server/queries/customer-portal-loyalty-tier.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltyTierCards } from "./customer-loyalty-tier-panel.tsx";

/**
 * Membership Tier card (CPL-317, CG-S13-CPL-019). Read-only customer-safe
 * view over Loyalty-owned app.loyalty_tier_definitions/app.loyalty_account_
 * tier_movements/app.loyalty_account_tier_holds (ADR-0024 Part A) -- current
 * tier, progress toward the next tier, benefits (suppressed with a generic
 * customer-safe message when a fraud hold is active), and the account's own
 * next review date. There is no customer-initiated action on this page
 * (ADR-0024 Part B) -- tier configuration, recalculation and holds are all
 * staff-side (app/(tenant)/[tenantSlug]/admin/loyalty-tiers).
 */
export default async function CustomerLoyaltyTierPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={access.status === "tenant_suspended" ? "This organization's customer portal is currently unavailable." : "You don't have access to this organization's membership tier. Contact your account administrator if you believe this is a mistake."}
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let cards: Awaited<ReturnType<typeof listCustomerPortalLoyaltyTierCards>> = [];

  try {
    cards = await listCustomerPortalLoyaltyTierCards(supabase, access.tenant.id, access.authUserId, { limit: 50 });
  } catch (error) {
    if (!(error instanceof LoyaltyTierQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="loyalty-tier" />
        <ErrorState description="Something went wrong loading your membership tier. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="loyalty-tier" />

      <div>
        <h1 className="text-xl font-semibold text-text-primary">Membership tier</h1>
        <p className="text-xs text-text-secondary">Your current tier, progress toward the next tier, and your tier&apos;s own benefits. Tiers are recalculated by your provider based on eligible earning -- never self-adjusted.</p>
      </div>

      <CustomerLoyaltyTierCards cards={cards} />
    </div>
  );
}
