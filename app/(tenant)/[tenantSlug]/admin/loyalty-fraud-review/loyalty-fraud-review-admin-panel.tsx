"use client";

import { useActionState } from "react";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { LOYALTY_FRAUD_RISK_SIGNAL_TYPES, type LoyaltyFraudReviewCase, type LoyaltyFraudReviewSuppression } from "../../../../../server/contracts/customer-portal-loyalty-expiry-fraud/customer-portal-loyalty-expiry-fraud.ts";
import {
  openLoyaltyFraudReviewCaseAction,
  claimLoyaltyFraudReviewCaseAction,
  confirmLoyaltyFraudReviewCaseAction,
  clearLoyaltyFraudReviewCaseAction,
  suppressLoyaltyFraudReviewAction,
  revokeLoyaltyFraudReviewSuppressionAction,
  type LoyaltyFraudReviewAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyFraudReviewAdminFormState = { error: null };

const STATUS_TONE: Record<LoyaltyFraudReviewCase["status"], StatusTone> = {
  open: "warning",
  under_review: "info",
  confirmed: "danger",
  cleared: "success",
};

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-xs text-danger">
      {error}
    </p>
  );
}

export function OpenLoyaltyFraudReviewCaseForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(openLoyaltyFraudReviewCaseAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} noValidate className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <p className="text-sm font-semibold text-text-primary">Open a fraud review case</p>
      <p className="text-xs text-text-secondary">Immediately applies a provisional hold on the account. No autonomous punitive action -- a human reviewer must later confirm or clear.</p>
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor="ofrc-account" className="block text-xs font-medium text-text-secondary">
            Loyalty account id
          </label>
          <input id="ofrc-account" name="loyaltyAccountId" type="text" required className="w-72 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
        </div>
        <div>
          <label htmlFor="ofrc-signal" className="block text-xs font-medium text-text-secondary">
            Risk signal type
          </label>
          <select id="ofrc-signal" name="riskSignalType" required className="w-48 rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
            {LOYALTY_FRAUD_RISK_SIGNAL_TYPES.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>
      </div>
      <div>
        <label htmlFor="ofrc-detail" className="block text-xs font-medium text-text-secondary">
          Internal risk signal detail (never shown to the customer)
        </label>
        <textarea id="ofrc-detail" name="riskSignalDetail" required rows={2} className="w-full max-w-2xl rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      </div>
      <Button type="submit" loading={pending} loadingLabel="Opening case…" className="w-fit">
        Open case
      </Button>
      <ErrorBanner error={state.error} />
    </form>
  );
}

function CaseRow({ tenantSlug, fraudCase }: { tenantSlug: string; fraudCase: LoyaltyFraudReviewCase }) {
  const [claimState, claimAction, claimPending] = useActionState(claimLoyaltyFraudReviewCaseAction.bind(null, tenantSlug, fraudCase.id, fraudCase.recordVersion), INITIAL_STATE);
  const [confirmState, confirmAction, confirmPending] = useActionState(confirmLoyaltyFraudReviewCaseAction.bind(null, tenantSlug, fraudCase.id, fraudCase.recordVersion), INITIAL_STATE);
  const [clearState, clearAction, clearPending] = useActionState(clearLoyaltyFraudReviewCaseAction.bind(null, tenantSlug, fraudCase.id, fraudCase.recordVersion), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-sm font-semibold text-text-primary">Account {fraudCase.loyaltyAccountId.slice(0, 8)}…</p>
          <p className="text-xs text-text-secondary">
            {fraudCase.riskSignalType} &middot; opened by {fraudCase.openedBy ?? "—"}
          </p>
          <p className="text-xs text-text-secondary">{fraudCase.riskSignalDetail}</p>
        </div>
        <StatusBadge tone={STATUS_TONE[fraudCase.status]} label={fraudCase.status} />
      </div>

      <div className="flex flex-wrap items-end gap-3">
        {fraudCase.status === "open" ? (
          <form action={claimAction} noValidate>
            <Button type="submit" variant="secondary" loading={claimPending} loadingLabel="Claiming…" className="w-fit">
              Claim for review
            </Button>
          </form>
        ) : null}

        <form action={confirmAction} noValidate className="flex flex-wrap items-end gap-2">
          <div>
            <label htmlFor={`confirm-reason-${fraudCase.id}`} className="sr-only">
              Confirm reason
            </label>
            <input id={`confirm-reason-${fraudCase.id}`} name="reviewReason" type="text" required placeholder="Confirm reason (required)" className="w-56 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
          </div>
          <Button type="submit" variant="secondary" loading={confirmPending} loadingLabel="Confirming…" className="w-fit">
            Confirm (keep hold)
          </Button>
        </form>

        <form action={clearAction} noValidate className="flex flex-wrap items-end gap-2">
          <div>
            <label htmlFor={`clear-reason-${fraudCase.id}`} className="sr-only">
              Clear reason
            </label>
            <input id={`clear-reason-${fraudCase.id}`} name="reviewReason" type="text" required placeholder="Clear reason (required)" className="w-56 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
          </div>
          <Button type="submit" loading={clearPending} loadingLabel="Clearing…" className="w-fit">
            Clear (release hold)
          </Button>
        </form>
      </div>
      <ErrorBanner error={claimState.error} />
      <ErrorBanner error={confirmState.error} />
      <ErrorBanner error={clearState.error} />
    </div>
  );
}

export function LoyaltyFraudReviewCaseQueue({ tenantSlug, cases }: { tenantSlug: string; cases: readonly LoyaltyFraudReviewCase[] }) {
  if (cases.length === 0) {
    return <EmptyState title="No open fraud review cases" description="Every opened case has already been confirmed or cleared." />;
  }
  return (
    <div className="flex flex-col gap-3">
      {cases.map((fraudCase) => (
        <CaseRow key={fraudCase.id} tenantSlug={tenantSlug} fraudCase={fraudCase} />
      ))}
    </div>
  );
}

export function LoyaltyFraudReviewCaseHistoryTable({ cases }: { cases: readonly LoyaltyFraudReviewCase[] }) {
  if (cases.length === 0) {
    return <EmptyState title="No decided cases yet" description="Confirmed/cleared cases will appear here." />;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[640px] text-left text-sm">
        <thead>
          <tr className="border-b border-neutral-200 text-xs text-text-secondary">
            <th className="py-2 pr-3">Account</th>
            <th className="py-2 pr-3">Signal</th>
            <th className="py-2 pr-3">Status</th>
            <th className="py-2 pr-3">Reviewed by</th>
            <th className="py-2 pr-3">Decided</th>
          </tr>
        </thead>
        <tbody>
          {cases.map((fraudCase) => (
            <tr key={fraudCase.id} className="border-b border-neutral-100">
              <td className="py-2 pr-3">{fraudCase.loyaltyAccountId.slice(0, 8)}…</td>
              <td className="py-2 pr-3">{fraudCase.riskSignalType}</td>
              <td className="py-2 pr-3">
                <StatusBadge tone={STATUS_TONE[fraudCase.status]} label={fraudCase.status} />
              </td>
              <td className="py-2 pr-3">{fraudCase.reviewedBy ?? "—"}</td>
              <td className="py-2 pr-3">{fraudCase.decidedAt ? new Date(fraudCase.decidedAt).toLocaleString() : "—"}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

export function SuppressLoyaltyFraudReviewForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(suppressLoyaltyFraudReviewAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} noValidate className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <p className="text-sm font-semibold text-text-primary">Suppress fraud review for an account</p>
      <p className="text-xs text-text-secondary">Prevents a NEW review case from being opened while active -- for example, after clearing a verified false positive.</p>
      <div className="flex flex-wrap items-end gap-3">
        <div>
          <label htmlFor="sup-account" className="block text-xs font-medium text-text-secondary">
            Loyalty account id
          </label>
          <input id="sup-account" name="loyaltyAccountId" type="text" required className="w-72 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
        </div>
        <div>
          <label htmlFor="sup-days" className="block text-xs font-medium text-text-secondary">
            Days
          </label>
          <input id="sup-days" name="days" type="number" min={1} defaultValue={7} required className="w-24 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
        </div>
      </div>
      <div>
        <label htmlFor="sup-reason" className="block text-xs font-medium text-text-secondary">
          Reason
        </label>
        <input id="sup-reason" name="reason" type="text" required placeholder="Reason (required)" className="w-full max-w-xl rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      </div>
      <Button type="submit" loading={pending} loadingLabel="Suppressing…" className="w-fit">
        Suppress
      </Button>
      <ErrorBanner error={state.error} />
    </form>
  );
}

function SuppressionRow({ tenantSlug, suppression }: { tenantSlug: string; suppression: LoyaltyFraudReviewSuppression }) {
  const [state, formAction, pending] = useActionState(revokeLoyaltyFraudReviewSuppressionAction.bind(null, tenantSlug, suppression.id, suppression.recordVersion), INITIAL_STATE);
  const isActive = !suppression.revokedAt;
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-sm font-semibold text-text-primary">Account {suppression.loyaltyAccountId.slice(0, 8)}…</p>
          <p className="text-xs text-text-secondary">{suppression.reason}</p>
          <p className="text-xs text-text-secondary">Expires {new Date(suppression.expiresAt).toLocaleString()}</p>
        </div>
        <StatusBadge tone={isActive ? "warning" : "neutral"} label={isActive ? "active" : "revoked"} />
      </div>
      {isActive ? (
        <form action={formAction} noValidate className="flex flex-wrap items-end gap-2">
          <div>
            <label htmlFor={`revoke-reason-${suppression.id}`} className="sr-only">
              Revoke reason
            </label>
            <input id={`revoke-reason-${suppression.id}`} name="reason" type="text" placeholder="Reason (optional)" className="w-56 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
          </div>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Revoking…" className="w-fit">
            Revoke
          </Button>
        </form>
      ) : null}
      <ErrorBanner error={state.error} />
    </div>
  );
}

export function LoyaltyFraudReviewSuppressionList({ tenantSlug, suppressions }: { tenantSlug: string; suppressions: readonly LoyaltyFraudReviewSuppression[] }) {
  if (suppressions.length === 0) {
    return <EmptyState title="No active suppressions" description="No account currently has fraud review suppressed." />;
  }
  return (
    <div className="flex flex-col gap-3">
      {suppressions.map((suppression) => (
        <SuppressionRow key={suppression.id} tenantSlug={tenantSlug} suppression={suppression} />
      ))}
    </div>
  );
}
