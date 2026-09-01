"use client";

import { useActionState } from "react";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../components/ui/button.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { describeLoyaltyRedemptionStatus, canCancelLoyaltyRedemption, type CustomerPortalLoyaltyRedemption } from "../../../../server/contracts/customer-portal-loyalty-redemptions/customer-portal-loyalty-redemptions.ts";
import { cancelLoyaltyRedemptionAction, type CancelLoyaltyRedemptionFormState } from "./actions.ts";

const INITIAL_STATE: CancelLoyaltyRedemptionFormState = { error: null };

const STATUS_TONE: Record<CustomerPortalLoyaltyRedemption["status"], StatusTone> = {
  pending_approval: "warning",
  approved: "info",
  rejected: "neutral",
  fulfilling: "info",
  fulfilled: "success",
  cancelled: "neutral",
  failed: "danger",
};

const REWARD_TYPE_LABEL: Record<CustomerPortalLoyaltyRedemption["rewardType"], string> = {
  discount_voucher: "Discount voucher",
  physical_item: "Physical item",
  service_credit: "Service credit",
};

function CancelForm({ tenantSlug, redemption }: { tenantSlug: string; redemption: CustomerPortalLoyaltyRedemption }) {
  const [state, formAction, pending] = useActionState(cancelLoyaltyRedemptionAction.bind(null, tenantSlug, redemption.redemptionId, redemption.recordVersion), INITIAL_STATE);
  return (
    <form action={formAction} noValidate className="flex flex-col items-end gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Cancelling…" className="w-fit">
        Cancel request
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function RedemptionCard({ tenantSlug, redemption }: { tenantSlug: string; redemption: CustomerPortalLoyaltyRedemption }) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-xs font-medium text-text-secondary">{REWARD_TYPE_LABEL[redemption.rewardType]}</p>
          <p className="text-sm font-semibold text-text-primary">{redemption.rewardName}</p>
          {redemption.pointsConsumed > 0 ? <p className="text-xs text-text-secondary">{redemption.pointsConsumed} points</p> : null}
        </div>
        <StatusBadge tone={STATUS_TONE[redemption.status]} label={describeLoyaltyRedemptionStatus(redemption)} />
      </div>

      {redemption.decisionReason && redemption.status === "rejected" ? <p className="text-xs text-text-secondary">Reason: {redemption.decisionReason}</p> : null}
      {redemption.status === "fulfilled" && redemption.benefitEntitlementId ? <p className="text-xs text-text-secondary">Your voucher is in Cashback &amp; vouchers.</p> : null}

      {canCancelLoyaltyRedemption(redemption) ? <CancelForm tenantSlug={tenantSlug} redemption={redemption} /> : null}
    </div>
  );
}

export function CustomerLoyaltyRedemptionHistory({ tenantSlug, redemptions }: { tenantSlug: string; redemptions: readonly CustomerPortalLoyaltyRedemption[] }) {
  if (redemptions.length === 0) {
    return <EmptyState title="No redemptions yet" description="Redeem a reward from the reward catalogue and it will appear here." />;
  }
  return (
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      {redemptions.map((redemption) => (
        <RedemptionCard key={redemption.redemptionId} tenantSlug={tenantSlug} redemption={redemption} />
      ))}
    </div>
  );
}
