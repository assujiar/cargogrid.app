"use client";

/**
 * Points Ledger admin client forms (CPL-318, CG-S13-CPL-020). Same
 * `useActionState`/bound-action split every prior capability's own
 * create-form already uses (e.g. `admin/loyalty-tiers/loyalty-tier-admin-
 * panel.tsx`).
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { LoyaltyAccount } from "../../../../../server/contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";
import type { LoyaltyPointBalance, LoyaltyPointLot, LoyaltyPointAdjustmentRequest, LoyaltyPointAdjustmentStatus } from "../../../../../server/contracts/customer-portal-loyalty-points/customer-portal-loyalty-points.ts";
import {
  postLoyaltyPointsEarnedAction,
  reverseLoyaltyPointsEarnedAction,
  expireLoyaltyPointLotsAction,
  requestLoyaltyPointAdjustmentAction,
  decideLoyaltyPointAdjustmentAction,
  type LoyaltyPointsAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyPointsAdminFormState = { error: null, notice: null };

const ADJUSTMENT_STATUS_TONE: Record<LoyaltyPointAdjustmentStatus, StatusTone> = { pending_approval: "warning", approved: "success", rejected: "neutral" };

function FormFeedback({ state }: { state: LoyaltyPointsAdminFormState }) {
  return (
    <>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      {state.notice ? <p className="text-sm text-success">{state.notice}</p> : null}
    </>
  );
}

export function PostPointsEarnedForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(postLoyaltyPointsEarnedAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-1 flex-col gap-2 rounded-md border border-neutral-100 p-3" noValidate>
      <h3 className="text-xs font-semibold text-text-primary">Sync points from earning event</h3>
      <label htmlFor="pts-earn-event" className="text-xs font-medium text-text-secondary">
        Earning event ID
      </label>
      <input id="pts-earn-event" name="earningEventId" type="text" required placeholder="uuid" className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
      <label htmlFor="pts-earn-expiry" className="text-xs font-medium text-text-secondary">
        Expiry window (days, 1-3650)
      </label>
      <input id="pts-earn-expiry" name="expiryDays" type="number" step="1" min="1" max="3650" defaultValue={365} className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <FormFeedback state={state} />
      <Button type="submit" loading={pending} loadingLabel="Posting…" className="w-fit">
        Post earn entry
      </Button>
    </form>
  );
}

export function ReversePointsEarnedForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(reverseLoyaltyPointsEarnedAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-1 flex-col gap-2 rounded-md border border-neutral-100 p-3" noValidate>
      <h3 className="text-xs font-semibold text-text-primary">Reverse points for a reversed earning event</h3>
      <label htmlFor="pts-reversal-event" className="text-xs font-medium text-text-secondary">
        Reversal earning event ID
      </label>
      <input id="pts-reversal-event" name="reversalEarningEventId" type="text" required placeholder="uuid" className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs" />
      <FormFeedback state={state} />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Posting…" className="w-fit">
        Post reversal entry
      </Button>
    </form>
  );
}

export function ExpireLotsForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(expireLoyaltyPointLotsAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} noValidate>
      <FormFeedback state={state} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Scanning…" className="mt-2 w-fit">
        Run expiry scan
      </Button>
    </form>
  );
}

export function RequestAdjustmentForm({ tenantSlug, accounts }: { tenantSlug: string; accounts: readonly LoyaltyAccount[] }) {
  const [state, formAction, pending] = useActionState(requestLoyaltyPointAdjustmentAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <label htmlFor="pts-adj-account" className="text-xs font-medium text-text-secondary">
        Loyalty account
      </label>
      <select id="pts-adj-account" name="loyaltyAccountId" required className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
        <option value="">Select an account…</option>
        {accounts.map((account) => (
          <option key={account.id} value={account.id}>
            {account.customerAccountId}
          </option>
        ))}
      </select>
      <label htmlFor="pts-adj-amount" className="text-xs font-medium text-text-secondary">
        Adjustment amount (points; negative to deduct)
      </label>
      <input id="pts-adj-amount" name="adjustmentAmount" type="number" step="1" required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label htmlFor="pts-adj-reason" className="text-xs font-medium text-text-secondary">
        Reason (required, visible to staff only)
      </label>
      <textarea id="pts-adj-reason" name="reason" rows={2} required className="w-full rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <FormFeedback state={state} />
      <Button type="submit" loading={pending} loadingLabel="Submitting…" className="w-fit">
        Submit request
      </Button>
    </form>
  );
}

export function AdjustmentRequestRow({ tenantSlug, request }: { tenantSlug: string; request: LoyaltyPointAdjustmentRequest }) {
  const [approveState, approveAction, approvePending] = useActionState(decideLoyaltyPointAdjustmentAction.bind(null, tenantSlug, request.id, request.recordVersion, "approved"), INITIAL_STATE);
  const [rejectState, rejectAction, rejectPending] = useActionState(decideLoyaltyPointAdjustmentAction.bind(null, tenantSlug, request.id, request.recordVersion, "rejected"), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="font-mono text-xs text-text-secondary">{request.loyaltyAccountId}</p>
          <p className="text-sm font-medium text-text-primary">
            {request.adjustmentAmount >= 0 ? "+" : ""}
            {request.adjustmentAmount.toFixed(0)} points -- requested by {request.requestedBy ?? request.requestedByAuthUserId}
          </p>
          <p className="text-xs text-text-secondary">{request.reason}</p>
        </div>
        <StatusBadge tone={ADJUSTMENT_STATUS_TONE[request.status] ?? "neutral"} label={request.status.replace("_", " ")} />
      </div>

      {request.status === "pending_approval" ? (
        <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
          <form action={approveAction} className="flex flex-1 items-end gap-2" noValidate>
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor={`pts-adj-notes-approve-${request.id}`} className="text-xs font-medium text-text-secondary">
                Decision notes (required)
              </label>
              <input id={`pts-adj-notes-approve-${request.id}`} name="decisionNotes" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
            </div>
            <Button type="submit" loading={approvePending} loadingLabel="Approving…" className="w-fit">
              Approve
            </Button>
          </form>
          <form action={rejectAction} className="flex flex-1 items-end gap-2" noValidate>
            <div className="flex flex-1 flex-col gap-1">
              <label htmlFor={`pts-adj-notes-reject-${request.id}`} className="text-xs font-medium text-text-secondary">
                Decision notes (required)
              </label>
              <input id={`pts-adj-notes-reject-${request.id}`} name="decisionNotes" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
            </div>
            <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…" className="w-fit">
              Reject
            </Button>
          </form>
        </div>
      ) : (
        <p className="text-xs text-text-secondary">
          {request.status} by {request.decidedBy ?? request.decidedByAuthUserId} -- {request.decisionNotes}
        </p>
      )}
      <FormFeedback state={request.status === "pending_approval" ? approveState : INITIAL_STATE} />
      {request.status === "pending_approval" ? <FormFeedback state={rejectState} /> : null}
    </div>
  );
}

export function AccountBalanceRow({ tenantSlug: _tenantSlug, account, balance, lots }: { tenantSlug: string; account: LoyaltyAccount; balance: LoyaltyPointBalance | null; lots: readonly LoyaltyPointLot[] }) {
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <p className="font-mono text-xs text-text-secondary">{account.customerAccountId}</p>
        <p className="text-sm font-medium text-text-primary">{balance ? `${balance.available.toFixed(0)} available` : "No point activity yet"}</p>
      </div>
      {balance ? (
        <p className="text-xs text-text-secondary">
          {balance.totalEarned.toFixed(0)} earned lifetime, {balance.totalConsumed.toFixed(0)} used
        </p>
      ) : null}
      {lots.length > 0 ? (
        <div className="overflow-x-auto">
          <table className="w-full border-collapse text-xs">
            <caption className="sr-only">Active lots for {account.customerAccountId}</caption>
            <thead>
              <tr className="text-left font-medium text-text-secondary">
                <th className="p-1">Lot</th>
                <th className="p-1 text-right">Remaining</th>
                <th className="p-1">Expires</th>
              </tr>
            </thead>
            <tbody>
              {lots.map((lot) => (
                <tr key={lot.id} className="border-t border-neutral-100">
                  <td className="p-1 font-mono">{lot.id.slice(0, 8)}</td>
                  <td className="p-1 text-right tabular-nums">
                    {lot.remainingAmount.toFixed(0)} / {lot.originalAmount.toFixed(0)}
                  </td>
                  <td className="p-1">{new Date(lot.expiresAt).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      ) : null}
    </div>
  );
}
