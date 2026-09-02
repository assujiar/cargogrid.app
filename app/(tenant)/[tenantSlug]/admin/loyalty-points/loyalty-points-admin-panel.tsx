"use client";

/**
 * Points Ledger admin client forms (CPL-318, CG-S13-CPL-020). Same
 * `useActionState`/bound-action split every prior capability's own
 * create-form already uses (e.g. `admin/loyalty-tiers/loyalty-tier-admin-
 * panel.tsx`).
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { useToastOnSettled } from "../../../../../components/ui/toast.tsx";
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

/**
 * ISS-2026-242: `errorId` is what this form's controls point their `aria-describedby` at.
 *
 * ISS-2026-246: `state.notice` used to render as a bare `<p className="text-sm text-success">`
 * -- a colour-coded line with no live-region semantics, so a screen-reader user was never told
 * the ledger posting had succeeded at all. Every one of this panel's five notices is a short,
 * self-contained outcome sentence with nothing to copy out of it and no follow-up instruction
 * ("Posted a 500-point earn entry.", "Expired 3 lot(s).", "Adjustment approved and posted to the
 * ledger."), which is exactly the transient confirmation `Toast` exists for. Errors deliberately
 * stay inline: `ValidationMessage` is what the controls' `aria-describedby` points at, and a
 * message that auto-dismisses after four seconds is the wrong home for something the user has to
 * act on.
 */
function FormFeedback({ state, pending, errorId }: { state: LoyaltyPointsAdminFormState; pending: boolean; errorId?: string }) {
  useToastOnSettled(pending, state.notice ? { title: state.notice, tone: "success" } : null);

  return state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null;
}

export function PostPointsEarnedForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(postLoyaltyPointsEarnedAction.bind(null, tenantSlug), INITIAL_STATE);
  const describedBy = state.error ? "pts-earn-error" : undefined;
  return (
    <form action={formAction} className="flex flex-1 flex-col gap-2 rounded-md border border-neutral-100 p-3" noValidate>
      <h3 className="text-xs font-semibold text-text-primary">Sync points from earning event</h3>
      <FormField id="pts-earn-event" label="Earning event ID">
        <Input id="pts-earn-event" name="earningEventId" type="text" required placeholder="uuid" className="font-mono text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="pts-earn-expiry" label="Expiry window (days, 1-3650)">
        <NumberInput id="pts-earn-expiry" name="expiryDays" step="1" min="1" max="3650" defaultValue={365} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormFeedback state={state} pending={pending} errorId="pts-earn-error" />
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
      <FormField id="pts-reversal-event" label="Reversal earning event ID">
        <Input
          id="pts-reversal-event"
          name="reversalEarningEventId"
          type="text"
          required
          placeholder="uuid"
          className="font-mono text-xs"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? "pts-reversal-error" : undefined}
        />
      </FormField>
      <FormFeedback state={state} pending={pending} errorId="pts-reversal-error" />
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
      <FormFeedback state={state} pending={pending} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Scanning…" className="mt-2 w-fit">
        Run expiry scan
      </Button>
    </form>
  );
}

export function RequestAdjustmentForm({ tenantSlug, accounts }: { tenantSlug: string; accounts: readonly LoyaltyAccount[] }) {
  const [state, formAction, pending] = useActionState(requestLoyaltyPointAdjustmentAction.bind(null, tenantSlug), INITIAL_STATE);
  // ISS-2026-242: one action error covers all three fields, so each points at the shared message.
  const describedBy = state.error ? "pts-adj-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <FormField id="pts-adj-account" label="Loyalty account">
        <Select id="pts-adj-account" name="loyaltyAccountId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">Select an account…</option>
          {accounts.map((account) => (
            <option key={account.id} value={account.id}>
              {account.customerAccountId}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="pts-adj-amount" label="Adjustment amount (points; negative to deduct)">
        <NumberInput id="pts-adj-amount" name="adjustmentAmount" step="1" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="pts-adj-reason" label="Reason (required, visible to staff only)">
        <Textarea id="pts-adj-reason" name="reason" rows={2} required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormFeedback state={state} pending={pending} errorId="pts-adj-error" />
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
            <div className="flex-1">
              <FormField id={`pts-adj-notes-approve-${request.id}`} label="Decision notes (required)">
                <Input
                  id={`pts-adj-notes-approve-${request.id}`}
                  name="decisionNotes"
                  required
                  className="text-xs"
                  invalid={Boolean(approveState.error)}
                  aria-describedby={approveState.error ? `pts-adj-approve-${request.id}-error` : undefined}
                />
              </FormField>
            </div>
            <Button type="submit" loading={approvePending} loadingLabel="Approving…" className="w-fit">
              Approve
            </Button>
          </form>
          <form action={rejectAction} className="flex flex-1 items-end gap-2" noValidate>
            <div className="flex-1">
              <FormField id={`pts-adj-notes-reject-${request.id}`} label="Decision notes (required)">
                <Input
                  id={`pts-adj-notes-reject-${request.id}`}
                  name="decisionNotes"
                  required
                  className="text-xs"
                  invalid={Boolean(rejectState.error)}
                  aria-describedby={rejectState.error ? `pts-adj-reject-${request.id}-error` : undefined}
                />
              </FormField>
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
      <FormFeedback state={request.status === "pending_approval" ? approveState : INITIAL_STATE} pending={request.status === "pending_approval" ? approvePending : false} errorId={`pts-adj-approve-${request.id}-error`} />
      {request.status === "pending_approval" ? <FormFeedback state={rejectState} pending={rejectPending} errorId={`pts-adj-reject-${request.id}-error`} /> : null}
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
