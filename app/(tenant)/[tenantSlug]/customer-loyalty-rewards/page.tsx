import { redirect } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyAccounts, LoyaltyProgramQueryError } from "../../../../server/queries/customer-portal-loyalty-program.ts";
import { listCustomerPortalLoyaltyRewards, LoyaltyRewardQueryError } from "../../../../server/queries/customer-portal-loyalty-rewards.ts";
import type { CustomerPortalLoyaltyReward } from "../../../../server/contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";
import { PermissionState } from "../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../components/ui/error-state.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { CustomerPortalNav } from "../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltyRewardCatalogue } from "./customer-loyalty-rewards-panel.tsx";

/**
 * Reward Catalogue (CPL-320, CG-S13-CPL-022). Read-only customer-safe view
 * over Loyalty-owned app.loyalty_rewards (ADR-0024 Part A) -- eligible/
 * locked/out_of_stock/unavailable states, computed live against the
 * customer's own current tier/points standing. There is no customer-
 * initiated action on this page (this is a catalogue-only capability) --
 * reward configuration, publish/pause/resume/archive, and stock reservation
 * are all staff-side (app/(tenant)/[tenantSlug]/admin/loyalty-rewards).
 * Redemption itself does not exist yet anywhere in this repository --
 * CPL-321's own future scope, disclosed in the migration's own header.
 *
 * A loyalty_account is required per reward-catalogue call (unlike the
 * sibling tier/points/benefits reads, which resolve across the caller's
 * WHOLE scope) -- CPL-316's own business rule caps ACTIVE accounts at ONE
 * per customer tenant-wide, so this resolves to at most one catalogue
 * section in practice; the shape below still handles more than one active
 * account defensively, rather than silently picking the first.
 */
export default async function CustomerLoyaltyRewardsPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);

  if (access.status === "unauthenticated") {
    redirect(`/login`);
  }

  if (access.status !== "allowed") {
    return (
      <PermissionState
        description={access.status === "tenant_suspended" ? "This organization's customer portal is currently unavailable." : "You don't have access to this organization's reward catalogue. Contact your account administrator if you believe this is a mistake."}
      />
    );
  }

  const supabase = await createSupabaseServerClient();
  let loadFailed = false;
  let accounts: Awaited<ReturnType<typeof listCustomerPortalLoyaltyAccounts>> = [];
  let sections: { loyaltyAccountId: string; programName: string; rewards: CustomerPortalLoyaltyReward[] }[] = [];

  try {
    accounts = await listCustomerPortalLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { limit: 50 });
    const activeAccounts = accounts.filter((account) => account.status === "active");
    sections = await Promise.all(
      activeAccounts.map(async (account) => ({
        loyaltyAccountId: account.id,
        programName: account.programName,
        rewards: await listCustomerPortalLoyaltyRewards(supabase, access.tenant.id, account.id, access.authUserId, { limit: 200 }),
      })),
    );
  } catch (error) {
    if (!(error instanceof LoyaltyProgramQueryError) && !(error instanceof LoyaltyRewardQueryError)) throw error;
    loadFailed = true;
  }

  if (loadFailed) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="rewards" />
        <ErrorState description="Something went wrong loading the reward catalogue. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="rewards" />

      <div>
        <h1 className="text-xl font-semibold text-text-primary">Reward catalogue</h1>
        <p className="text-xs text-text-secondary">Rewards you can redeem based on your tier and points. Eligibility is checked again at the time of redemption -- seeing a reward here does not guarantee it stays available.</p>
      </div>

      {sections.length === 0 ? (
        <EmptyState title="No active loyalty enrollment" description="Enroll in a loyalty program to see its reward catalogue. Contact your account administrator or your CargoGrid representative." />
      ) : (
        sections.map((section) => <CustomerLoyaltyRewardCatalogue key={section.loyaltyAccountId} tenantSlug={tenantSlug} loyaltyAccountId={section.loyaltyAccountId} programName={section.programName} rewards={section.rewards} />)
      )}
    </div>
  );
}
