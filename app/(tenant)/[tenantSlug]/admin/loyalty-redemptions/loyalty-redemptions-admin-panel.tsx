"use client";

import { useActionState } from "react";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { LoyaltyRedemption } from "../../../../../server/contracts/customer-portal-loyalty-redemptions/customer-portal-loyalty-redemptions.ts";
import {
  approveLoyaltyRedemptionAction,
  rejectLoyaltyRedemptionAction,
  markLoyaltyRedemptionFulfilledAction,
  markLoyaltyRedemptionFulfillmentFailedAction,
  type LoyaltyRedemptionAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyRedemptionAdminFormState = { error: null };

const STATUS_TONE: Record<LoyaltyRedemption["status"], StatusTone> = {
  pending_approval: "warning",
  approved: "info",
  rejected: "neutral",
  fulfilling: "info",
  fulfilled: "success",
  cancelled: "neutral",
  failed: "danger",
};

/** ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby` points at. */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return <ValidationMessage id={id}>{error}</ValidationMessage>;
}

function RedemptionSummary({ redemption }: { redemption: LoyaltyRedemption }) {
  return (
    <div>
      <p className="text-sm font-semibold text-text-primary">{redemption.rewardName}</p>
      <p className="text-xs text-text-secondary">
        {redemption.rewardType} &middot; {redemption.pointsConsumed} points &middot; account {redemption.loyaltyAccountId.slice(0, 8)}…
      </p>
    </div>
  );
}

function ApproveRejectRow({ tenantSlug, redemption }: { tenantSlug: string; redemption: LoyaltyRedemption }) {
  const [approveState, approveAction, approvePending] = useActionState(approveLoyaltyRedemptionAction.bind(null, tenantSlug, redemption.id, redemption.recordVersion), INITIAL_STATE);
  const [rejectState, rejectAction, rejectPending] = useActionState(rejectLoyaltyRedemptionAction.bind(null, tenantSlug, redemption.id, redemption.recordVersion), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <RedemptionSummary redemption={redemption} />
        <StatusBadge tone={STATUS_TONE[redemption.status]} label={redemption.status} />
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <form action={approveAction} noValidate>
          <Button type="submit" loading={approvePending} loadingLabel="Approving…" className="w-fit">
            Approve
          </Button>
        </form>

        <form action={rejectAction} noValidate className="flex flex-wrap items-end gap-2">
          <div className="w-56">
            <label htmlFor={`reject-reason-${redemption.id}`} className="sr-only">
              Rejection reason
            </label>
            <Input
              id={`reject-reason-${redemption.id}`}
              name="reason"
              type="text"
              required
              placeholder="Reason (required)"
              invalid={Boolean(rejectState.error)}
              aria-describedby={rejectState.error ? `reject-${redemption.id}-error` : undefined}
            />
          </div>
          <Button type="submit" variant="secondary" loading={rejectPending} loadingLabel="Rejecting…" className="w-fit">
            Reject
          </Button>
        </form>
      </div>
      <ErrorBanner error={approveState.error} />
      <ErrorBanner id={`reject-${redemption.id}-error`} error={rejectState.error} />
    </div>
  );
}

function FulfillmentRow({ tenantSlug, redemption }: { tenantSlug: string; redemption: LoyaltyRedemption }) {
  const [fulfilledState, fulfilledAction, fulfilledPending] = useActionState(markLoyaltyRedemptionFulfilledAction.bind(null, tenantSlug, redemption.id, redemption.recordVersion), INITIAL_STATE);
  const [failedState, failedAction, failedPending] = useActionState(markLoyaltyRedemptionFulfillmentFailedAction.bind(null, tenantSlug, redemption.id, redemption.recordVersion), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <RedemptionSummary redemption={redemption} />
        <StatusBadge tone={STATUS_TONE[redemption.status]} label={redemption.fulfillmentStatus} />
      </div>

      <div className="flex flex-wrap items-end gap-3">
        <form action={fulfilledAction} noValidate>
          <Button type="submit" loading={fulfilledPending} loadingLabel="Marking fulfilled…" className="w-fit">
            Mark fulfilled
          </Button>
        </form>

        <form action={failedAction} noValidate className="flex flex-wrap items-end gap-2">
          <div className="w-56">
            <label htmlFor={`fail-reason-${redemption.id}`} className="sr-only">
              Fulfillment failure reason
            </label>
            <Input
              id={`fail-reason-${redemption.id}`}
              name="reason"
              type="text"
              required
              placeholder="Reason (required)"
              invalid={Boolean(failedState.error)}
              aria-describedby={failedState.error ? `fail-${redemption.id}-error` : undefined}
            />
          </div>
          <Button type="submit" variant="secondary" loading={failedPending} loadingLabel="Marking failed…" className="w-fit">
            Mark failed
          </Button>
        </form>
      </div>
      <ErrorBanner error={fulfilledState.error} />
      <ErrorBanner id={`fail-${redemption.id}-error`} error={failedState.error} />
    </div>
  );
}

export function LoyaltyRedemptionApprovalQueue({ tenantSlug, redemptions }: { tenantSlug: string; redemptions: readonly LoyaltyRedemption[] }) {
  if (redemptions.length === 0) {
    return <EmptyState title="No redemptions awaiting approval" description="Every submitted redemption has already been decided." />;
  }
  return (
    <div className="flex flex-col gap-3">
      {redemptions.map((redemption) => (
        <ApproveRejectRow key={redemption.id} tenantSlug={tenantSlug} redemption={redemption} />
      ))}
    </div>
  );
}

export function LoyaltyRedemptionFulfillmentQueue({ tenantSlug, redemptions }: { tenantSlug: string; redemptions: readonly LoyaltyRedemption[] }) {
  if (redemptions.length === 0) {
    return <EmptyState title="Nothing awaiting fulfillment" description="No approved physical_item/service_credit redemptions are currently in progress." />;
  }
  return (
    <div className="flex flex-col gap-3">
      {redemptions.map((redemption) => (
        <FulfillmentRow key={redemption.id} tenantSlug={tenantSlug} redemption={redemption} />
      ))}
    </div>
  );
}

export function LoyaltyRedemptionHistoryTable({ redemptions }: { redemptions: readonly LoyaltyRedemption[] }) {
  if (redemptions.length === 0) {
    return <EmptyState title="No redemption history yet" description="Decided/fulfilled redemptions will appear here." />;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] text-left text-sm">
        <thead>
          <tr className="border-b border-neutral-200 text-xs text-text-secondary">
            <th className="py-2 pr-3">Reward</th>
            <th className="py-2 pr-3">Type</th>
            <th className="py-2 pr-3">Status</th>
            <th className="py-2 pr-3">Fulfillment</th>
            <th className="py-2 pr-3">Decided by</th>
            <th className="py-2 pr-3">Updated</th>
          </tr>
        </thead>
        <tbody>
          {redemptions.map((redemption) => (
            <tr key={redemption.id} className="border-b border-neutral-100">
              <td className="py-2 pr-3">{redemption.rewardName}</td>
              <td className="py-2 pr-3">{redemption.rewardType}</td>
              <td className="py-2 pr-3">
                <StatusBadge tone={STATUS_TONE[redemption.status]} label={redemption.status} />
              </td>
              <td className="py-2 pr-3">{redemption.fulfillmentStatus}</td>
              <td className="py-2 pr-3">{redemption.decidedBy ?? "—"}</td>
              <td className="py-2 pr-3">{new Date(redemption.updatedAt).toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
