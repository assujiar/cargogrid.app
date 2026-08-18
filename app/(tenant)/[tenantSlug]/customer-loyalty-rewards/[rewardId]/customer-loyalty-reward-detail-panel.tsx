"use client";

import { useActionState } from "react";
import NextLink from "next/link";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { describeLoyaltyRewardEligibility, type CustomerPortalLoyaltyRewardDetail } from "../../../../../server/contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";
import { submitLoyaltyRedemptionAction, type SubmitLoyaltyRedemptionFormState } from "../actions.ts";

const DISPLAY_STATE_TONE = { eligible: "success", locked: "neutral", out_of_stock: "warning", unavailable: "neutral" } as const;
const DISPLAY_STATE_LABEL = { eligible: "Eligible", locked: "Locked", out_of_stock: "Out of stock", unavailable: "Unavailable" } as const;

const INITIAL_REDEEM_STATE: SubmitLoyaltyRedemptionFormState = { error: null, redemptionId: null, status: null };

function RedeemForm({ tenantSlug, loyaltyAccountId, rewardId }: { tenantSlug: string; loyaltyAccountId: string; rewardId: string }) {
  const [state, formAction, pending] = useActionState(submitLoyaltyRedemptionAction.bind(null, tenantSlug, loyaltyAccountId, rewardId), INITIAL_REDEEM_STATE);

  if (state.redemptionId) {
    return (
      <div className="flex flex-col gap-2 rounded-md bg-success/10 p-3 text-sm text-success-strong">
        <p role="status">{state.status === "fulfilled" ? "Redeemed! Check your redemption history for details." : "Redemption request submitted -- awaiting approval."}</p>
        <NextLink href={`/${tenantSlug}/customer-loyalty-redemptions`} className="text-xs font-medium underline underline-offset-2">
          View my redemptions &rarr;
        </NextLink>
      </div>
    );
  }

  return (
    <form action={formAction} noValidate>
      {state.error ? (
        <p role="alert" className="mb-2 text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Redeeming…" className="w-fit">
        Redeem this reward
      </Button>
    </form>
  );
}

function TermsFile({ reward }: { reward: CustomerPortalLoyaltyRewardDetail }) {
  if (!reward.hasTermsFile) return null;
  if (reward.termsFileScanStatus === "clean") {
    return (
      <p className="text-xs text-text-secondary">
        Terms document: <span className="font-medium text-text-primary">{reward.termsFileName}</span> ({reward.termsFileMimeType}, {((reward.termsFileSizeBytes ?? 0) / 1024).toFixed(0)} KB)
      </p>
    );
  }
  // Honestly surfaced, never hidden or defaulted to clean (mirrors
  // CPL-308's own established malware/quarantine disclosure discipline).
  return <p className="text-xs text-text-secondary">Terms document: not yet available ({reward.termsFileScanStatus === "infected" ? "under review" : "scan pending"}).</p>;
}

export function CustomerLoyaltyRewardDetailCard({ tenantSlug, loyaltyAccountId, reward }: { tenantSlug: string; loyaltyAccountId: string; reward: CustomerPortalLoyaltyRewardDetail }) {
  return (
    <div className="flex flex-col gap-4">
      <NextLink href={`/${tenantSlug}/customer-loyalty-rewards`} className="text-xs text-primary underline underline-offset-2">
        &larr; Back to reward catalogue
      </NextLink>

      <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-6">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div>
            <p className="text-xs font-medium text-text-secondary">{reward.programName}</p>
            <h1 className="text-xl font-semibold text-text-primary">{reward.rewardName}</h1>
          </div>
          <StatusBadge tone={DISPLAY_STATE_TONE[reward.displayState]} label={DISPLAY_STATE_LABEL[reward.displayState]} />
        </div>

        {reward.description ? <p className="text-sm text-text-secondary">{reward.description}</p> : null}

        <p className="rounded-md bg-neutral-50 p-3 text-sm text-text-primary">{describeLoyaltyRewardEligibility(reward)}</p>

        {reward.totalStock !== null ? (
          <p className="text-xs text-text-secondary">
            {reward.stockAvailable ?? 0} of {reward.totalStock} remaining
          </p>
        ) : null}

        {reward.termsText ? (
          <div>
            <p className="text-xs font-semibold text-text-primary">Terms</p>
            <p className="text-xs text-text-secondary">{reward.termsText}</p>
          </div>
        ) : null}

        <TermsFile reward={reward} />

        <p className="text-xs text-text-secondary">Seeing this reward here does not guarantee redemption -- eligibility and stock are checked again at the time of redemption.</p>

        {reward.displayState === "eligible" ? <RedeemForm tenantSlug={tenantSlug} loyaltyAccountId={loyaltyAccountId} rewardId={reward.rewardId} /> : null}
      </div>
    </div>
  );
}
