import NextLink from "next/link";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { describeLoyaltyRewardEligibility, type CustomerPortalLoyaltyReward } from "../../../../server/contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";

const DISPLAY_STATE_TONE = { eligible: "success", locked: "neutral", out_of_stock: "warning", unavailable: "neutral" } as const;
const DISPLAY_STATE_LABEL = { eligible: "Eligible", locked: "Locked", out_of_stock: "Out of stock", unavailable: "Unavailable" } as const;

function RewardCard({ tenantSlug, loyaltyAccountId, reward }: { tenantSlug: string; loyaltyAccountId: string; reward: CustomerPortalLoyaltyReward }) {
  return (
    <NextLink
      href={`/${tenantSlug}/customer-loyalty-rewards/${reward.rewardId}?loyaltyAccountId=${loyaltyAccountId}`}
      className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4 text-left no-underline hover:border-primary"
    >
      <div className="flex flex-wrap items-start justify-between gap-2">
        <p className="text-sm font-semibold text-text-primary">{reward.rewardName}</p>
        <StatusBadge tone={DISPLAY_STATE_TONE[reward.displayState]} label={DISPLAY_STATE_LABEL[reward.displayState]} />
      </div>
      {reward.description ? <p className="text-xs text-text-secondary">{reward.description}</p> : null}
      <p className="text-xs text-text-secondary">{describeLoyaltyRewardEligibility(reward)}</p>
      {reward.totalStock !== null ? (
        <p className="text-xs text-text-secondary">
          {reward.stockAvailable ?? 0} of {reward.totalStock} remaining
        </p>
      ) : null}
    </NextLink>
  );
}

export function CustomerLoyaltyRewardCatalogue({ tenantSlug, loyaltyAccountId, programName, rewards }: { tenantSlug: string; loyaltyAccountId: string; programName: string; rewards: readonly CustomerPortalLoyaltyReward[] }) {
  return (
    <section aria-labelledby={`rewards-${loyaltyAccountId}`} className="flex flex-col gap-3">
      <h2 id={`rewards-${loyaltyAccountId}`} className="text-sm font-semibold text-text-primary">
        {programName}
      </h2>
      {rewards.length === 0 ? (
        <EmptyState title="No rewards available yet" description="Check back later -- your provider has not published any rewards for this program yet." />
      ) : (
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {rewards.map((reward) => (
            <RewardCard key={reward.rewardId} tenantSlug={tenantSlug} loyaltyAccountId={loyaltyAccountId} reward={reward} />
          ))}
        </div>
      )}
    </section>
  );
}
