"use client";

import { useActionState } from "react";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { FormSection } from "../../../../../components/forms/form-section.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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

/** ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby` points at. */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return <ValidationMessage id={id}>{error}</ValidationMessage>;
}

export function OpenLoyaltyFraudReviewCaseForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(openLoyaltyFraudReviewCaseAction.bind(null, tenantSlug), INITIAL_STATE);
  // ISS-2026-242: the RPC returns one error for the whole case-open call, never per-field ones.
  const describedBy = state.error ? "ofrc-error" : undefined;
  return (
    <form action={formAction} noValidate className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      {/* ISS-2026-246: this heading + blurb pair was two <p> tags -- FormSection renders the real
          <h2> the pair was already imitating. */}
      <FormSection
        title="Open a fraud review case"
        description="Immediately applies a provisional hold on the account. No autonomous punitive action -- a human reviewer must later confirm or clear."
      >
        <div className="flex flex-wrap items-end gap-3">
          <div className="w-72">
            <FormField id="ofrc-account" label="Loyalty account id">
              <Input id="ofrc-account" name="loyaltyAccountId" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
          <div className="w-48">
            <FormField id="ofrc-signal" label="Risk signal type">
              <Select id="ofrc-signal" name="riskSignalType" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
                {LOYALTY_FRAUD_RISK_SIGNAL_TYPES.map((type) => (
                  <option key={type} value={type}>
                    {type}
                  </option>
                ))}
              </Select>
            </FormField>
          </div>
        </div>
        <FormField id="ofrc-detail" label="Internal risk signal detail (never shown to the customer)">
          <Textarea id="ofrc-detail" name="riskSignalDetail" required rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <Button type="submit" loading={pending} loadingLabel="Opening case…" className="w-fit">
          Open case
        </Button>
        <ErrorBanner id="ofrc-error" error={state.error} />
      </FormSection>
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
          <div className="w-56">
            <label htmlFor={`confirm-reason-${fraudCase.id}`} className="sr-only">
              Confirm reason
            </label>
            <Input
              id={`confirm-reason-${fraudCase.id}`}
              name="reviewReason"
              type="text"
              required
              placeholder="Confirm reason (required)"
              invalid={Boolean(confirmState.error)}
              aria-describedby={confirmState.error ? `confirm-${fraudCase.id}-error` : undefined}
            />
          </div>
          <Button type="submit" variant="secondary" loading={confirmPending} loadingLabel="Confirming…" className="w-fit">
            Confirm (keep hold)
          </Button>
        </form>

        <form action={clearAction} noValidate className="flex flex-wrap items-end gap-2">
          <div className="w-56">
            <label htmlFor={`clear-reason-${fraudCase.id}`} className="sr-only">
              Clear reason
            </label>
            <Input
              id={`clear-reason-${fraudCase.id}`}
              name="reviewReason"
              type="text"
              required
              placeholder="Clear reason (required)"
              invalid={Boolean(clearState.error)}
              aria-describedby={clearState.error ? `clear-${fraudCase.id}-error` : undefined}
            />
          </div>
          <Button type="submit" loading={clearPending} loadingLabel="Clearing…" className="w-fit">
            Clear (release hold)
          </Button>
        </form>
      </div>
      <ErrorBanner error={claimState.error} />
      <ErrorBanner id={`confirm-${fraudCase.id}-error`} error={confirmState.error} />
      <ErrorBanner id={`clear-${fraudCase.id}-error`} error={clearState.error} />
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
  const describedBy = state.error ? "sup-error" : undefined;
  return (
    <form action={formAction} noValidate className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      {/* ISS-2026-246: same heading + blurb pair as the case-open form above, same real <h2>. */}
      <FormSection
        title="Suppress fraud review for an account"
        description="Prevents a NEW review case from being opened while active -- for example, after clearing a verified false positive."
      >
        <div className="flex flex-wrap items-end gap-3">
          <div className="w-72">
            <FormField id="sup-account" label="Loyalty account id">
              <Input id="sup-account" name="loyaltyAccountId" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
          <div className="w-24">
            <FormField id="sup-days" label="Days">
              <NumberInput id="sup-days" name="days" min={1} defaultValue={7} required invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
        </div>
        <div className="max-w-xl">
          <FormField id="sup-reason" label="Reason">
            <Input id="sup-reason" name="reason" type="text" required placeholder="Reason (required)" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <Button type="submit" loading={pending} loadingLabel="Suppressing…" className="w-fit">
          Suppress
        </Button>
        <ErrorBanner id="sup-error" error={state.error} />
      </FormSection>
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
          <div className="w-56">
            <label htmlFor={`revoke-reason-${suppression.id}`} className="sr-only">
              Revoke reason
            </label>
            <Input
              id={`revoke-reason-${suppression.id}`}
              name="reason"
              type="text"
              placeholder="Reason (optional)"
              invalid={Boolean(state.error)}
              aria-describedby={state.error ? `revoke-suppression-${suppression.id}-error` : undefined}
            />
          </div>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Revoking…" className="w-fit">
            Revoke
          </Button>
        </form>
      ) : null}
      <ErrorBanner id={`revoke-suppression-${suppression.id}-error`} error={state.error} />
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
