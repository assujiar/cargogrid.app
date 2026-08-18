import { redirect, notFound } from "next/navigation";
import { resolveCustomerPortalAccessForRequest } from "../../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { listCustomerPortalLoyaltyAccounts, LoyaltyProgramQueryError } from "../../../../../server/queries/customer-portal-loyalty-program.ts";
import { getCustomerPortalLoyaltyReward, LoyaltyRewardQueryError } from "../../../../../server/queries/customer-portal-loyalty-rewards.ts";
import { PermissionState } from "../../../../../components/ui/permission-state.tsx";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { CustomerPortalNav } from "../../../../../components/domain/customer-portal-nav.tsx";
import { CustomerLoyaltyRewardDetailCard } from "./customer-loyalty-reward-detail-panel.tsx";

/**
 * Reward detail (CPL-320, CG-S13-CPL-022). Same eligibility/stock
 * projection as the catalogue list, for ONE reward, plus a malware-scan-
 * gated reference to its own terms file (migration design decision 9) --
 * mirrors CPL-307/CPL-308's own established private-file pattern, never a
 * fabricated signed URL. Now also carries a "Redeem this reward" checkout
 * action (CPL-321, CG-S13-CPL-023) when the reward's own displayState is
 * eligible -- server-side re-validation happens again, inside app.submit_
 * loyalty_redemption's own transaction, at the actual moment of redemption.
 */
export default async function CustomerLoyaltyRewardDetailPage({
  params,
  searchParams,
}: {
  params: Promise<{ tenantSlug: string; rewardId: string }>;
  searchParams: Promise<{ loyaltyAccountId?: string }>;
}) {
  const { tenantSlug, rewardId } = await params;
  const { loyaltyAccountId: loyaltyAccountIdParam } = await searchParams;
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
  let loyaltyAccountId = loyaltyAccountIdParam ?? null;

  if (!loyaltyAccountId) {
    // Resolve the caller's own first active loyalty account -- CPL-316's
    // own business rule caps ACTIVE accounts at ONE per customer
    // tenant-wide, so this is a safe fallback for a bookmarked/shared
    // detail link that never carried the query param.
    try {
      const accounts = await listCustomerPortalLoyaltyAccounts(supabase, access.tenant.id, access.authUserId, { limit: 50 });
      loyaltyAccountId = accounts.find((account) => account.status === "active")?.id ?? null;
    } catch (error) {
      if (!(error instanceof LoyaltyProgramQueryError)) throw error;
    }
  }

  if (!loyaltyAccountId) {
    notFound();
  }

  let reward: Awaited<ReturnType<typeof getCustomerPortalLoyaltyReward>> | null = null;
  let loadFailed = false;

  try {
    reward = await getCustomerPortalLoyaltyReward(supabase, access.tenant.id, rewardId, loyaltyAccountId, access.authUserId);
  } catch (error) {
    if (!(error instanceof LoyaltyRewardQueryError)) throw error;
    if (error.code === "loyalty_reward_not_found") {
      notFound();
    }
    loadFailed = true;
  }

  if (loadFailed || !reward) {
    return (
      <div className="flex flex-col gap-4">
        <CustomerPortalNav tenantSlug={tenantSlug} current="rewards" />
        <ErrorState description="Something went wrong loading this reward. Please try again." />
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-6">
      <CustomerPortalNav tenantSlug={tenantSlug} current="rewards" />
      <CustomerLoyaltyRewardDetailCard tenantSlug={tenantSlug} loyaltyAccountId={loyaltyAccountId} reward={reward} />
    </div>
  );
}
