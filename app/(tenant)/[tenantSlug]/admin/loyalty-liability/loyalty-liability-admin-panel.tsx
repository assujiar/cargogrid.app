"use client";

import { useActionState } from "react";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { FormSection } from "../../../../../components/forms/form-section.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { KpiCard } from "../../../../../components/ui/kpi-card.tsx";
import type { LoyaltyLiabilityReconciliationRun, LoyaltyLiabilityReconciliationException, LoyaltyEngagementMetrics } from "../../../../../server/contracts/customer-portal-loyalty-liability/customer-portal-loyalty-liability.ts";
import { describeLoyaltyLiabilityReconciliationRunStatus } from "../../../../../server/contracts/customer-portal-loyalty-liability/customer-portal-loyalty-liability.ts";
import {
  executeLoyaltyLiabilityReconciliationRunAction,
  resolveLoyaltyLiabilityReconciliationExceptionAction,
  certifyLoyaltyLiabilityReconciliationRunAction,
  type LoyaltyLiabilityAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyLiabilityAdminFormState = { error: null };

const STATUS_TONE: Record<LoyaltyLiabilityReconciliationRun["status"], StatusTone> = {
  open: "warning",
  exceptions_pending: "danger",
  certified: "success",
};

/** ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby` points at. */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return <ValidationMessage id={id}>{error}</ValidationMessage>;
}

function formatAmount(value: number): string {
  return new Intl.NumberFormat("en-US", { maximumFractionDigits: 2 }).format(value);
}

export function LoyaltyEngagementMetricsWidgets({ metrics }: { metrics: LoyaltyEngagementMetrics | null }) {
  if (!metrics) {
    return <EmptyState title="No engagement data yet" description="Engagement metrics will appear once loyalty activity exists for this tenant." />;
  }
  return (
    <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
      <KpiCard label="Active loyalty accounts" value={metrics.activeLoyaltyAccountsCount} />
      <KpiCard label="Points earned (period)" value={formatAmount(metrics.pointsEarnedTotal)} />
      <KpiCard label="Points redeemed (period)" value={formatAmount(metrics.pointsRedeemedTotal)} />
      <KpiCard label="Redemptions (period)" value={metrics.redemptionCount} />
      <KpiCard label="Redemption rate" value={`${(metrics.redemptionRate * 100).toFixed(1)}%`} trend="redemptions per active account" />
      <KpiCard label="Published rewards" value={metrics.publishedRewardCount} />
      <KpiCard label="Rewards with a redemption" value={metrics.rewardsWithRedemptionCount} />
    </div>
  );
}

export function ExecuteLoyaltyLiabilityReconciliationRunForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(executeLoyaltyLiabilityReconciliationRunAction.bind(null, tenantSlug), INITIAL_STATE);
  // ISS-2026-242: the run RPC returns one error covering all three inputs, never per-field ones.
  const describedBy = state.error ? "lrr-error" : undefined;
  return (
    <form action={formAction} noValidate className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      {/* ISS-2026-246: this heading + blurb pair was two <p> tags -- FormSection renders the real
          <h2> the pair was already imitating. */}
      <FormSection
        title="Run a liability reconciliation"
        description="Recomputes every liability total LIVE from the raw ledger/event tables -- points (a raw units total, never converted to currency), cashback/discount/voucher (scoped to the currency below), and open physical_item/service_credit reward-fulfillment exposure. Idempotent per (currency, day) unless you supply a distinct key."
      >
        <div className="flex flex-wrap items-end gap-3">
          <div className="w-24">
            <FormField id="lrr-currency" label="Currency">
              <Input
                id="lrr-currency"
                name="currency"
                type="text"
                required
                maxLength={3}
                placeholder="USD"
                defaultValue="USD"
                className="uppercase"
                invalid={Boolean(state.error)}
                aria-describedby={describedBy}
              />
            </FormField>
          </div>
          <div className="w-56">
            <FormField id="lrr-as-of" label="As of (optional)">
              <Input id="lrr-as-of" name="asOf" type="datetime-local" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
          <div className="w-64">
            <FormField id="lrr-idem" label="Idempotency key (optional)">
              <Input id="lrr-idem" name="idempotencyKey" type="text" placeholder="defaults to currency + today's date" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
          <Button type="submit" loading={pending} loadingLabel="Running…" className="w-fit">
            Run reconciliation
          </Button>
        </div>
        <ErrorBanner id="lrr-error" error={state.error} />
      </FormSection>
    </form>
  );
}

function CertifyRunButton({ tenantSlug, run }: { tenantSlug: string; run: LoyaltyLiabilityReconciliationRun }) {
  const [state, formAction, pending] = useActionState(certifyLoyaltyLiabilityReconciliationRunAction.bind(null, tenantSlug, run.id, run.recordVersion), INITIAL_STATE);
  if (run.status === "certified") {
    return <span className="text-xs text-text-secondary">Certified by {run.certifiedBy ?? "—"} on {run.certifiedAt ? new Date(run.certifiedAt).toLocaleString() : "—"}</span>;
  }
  return (
    <form action={formAction} noValidate className="flex flex-col items-start gap-1">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Certifying…" disabled={run.status === "exceptions_pending"} className="w-fit">
        Certify
      </Button>
      {run.status === "exceptions_pending" ? <span className="text-xs text-text-secondary">Blocked while any exception on this run is open.</span> : null}
      <ErrorBanner error={state.error} />
    </form>
  );
}

export function LoyaltyLiabilityReconciliationRunHistoryTable({ tenantSlug, runs }: { tenantSlug: string; runs: readonly LoyaltyLiabilityReconciliationRun[] }) {
  if (runs.length === 0) {
    return <EmptyState title="No reconciliation runs yet" description="Run a reconciliation above and it will appear here." />;
  }
  return (
    <div className="overflow-x-auto">
      <table className="w-full min-w-[960px] text-left text-sm">
        <thead>
          <tr className="border-b border-neutral-200 text-xs text-text-secondary">
            <th className="py-2 pr-3">Currency</th>
            <th className="py-2 pr-3">Status</th>
            <th className="py-2 pr-3">Points</th>
            <th className="py-2 pr-3">Cashback</th>
            <th className="py-2 pr-3">Discount</th>
            <th className="py-2 pr-3">Voucher</th>
            <th className="py-2 pr-3">Reward fulfillment</th>
            <th className="py-2 pr-3">As of</th>
            <th className="py-2 pr-3">Certify</th>
          </tr>
        </thead>
        <tbody>
          {runs.map((run) => (
            <tr key={run.id} className="border-b border-neutral-100 align-top">
              <td className="py-2 pr-3">{run.currency}</td>
              <td className="py-2 pr-3">
                <StatusBadge tone={STATUS_TONE[run.status]} label={describeLoyaltyLiabilityReconciliationRunStatus(run.status)} />
              </td>
              <td className="py-2 pr-3">{formatAmount(run.pointsLiabilityTotal)} pts</td>
              <td className="py-2 pr-3">{formatAmount(run.cashbackLiabilityTotal)}</td>
              <td className="py-2 pr-3">{formatAmount(run.discountLiabilityTotal)}</td>
              <td className="py-2 pr-3">{formatAmount(run.voucherLiabilityTotal)}</td>
              <td className="py-2 pr-3">{formatAmount(run.rewardFulfillmentLiabilityTotal)}</td>
              <td className="py-2 pr-3">{new Date(run.asOf).toLocaleString()}</td>
              <td className="py-2 pr-3">
                <CertifyRunButton tenantSlug={tenantSlug} run={run} />
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function ExceptionRow({ tenantSlug, exception, runCurrency }: { tenantSlug: string; exception: LoyaltyLiabilityReconciliationException; runCurrency: string }) {
  const [state, formAction, pending] = useActionState(resolveLoyaltyLiabilityReconciliationExceptionAction.bind(null, tenantSlug, exception.id, exception.recordVersion), INITIAL_STATE);
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-sm font-semibold text-text-primary">
            {exception.exceptionType === "point_balance_derivation_mismatch"
              ? "Point balance mismatch"
              : exception.exceptionType === "entitlement_state_derivation_mismatch"
                ? "Entitlement status mismatch"
                : exception.exceptionType === "redemption_liability_status_mismatch"
                  ? "Redemption liability status mismatch"
                  : "Reward internal cost missing"}
          </p>
          <p className="text-xs text-text-secondary">Run currency: {runCurrency}</p>
          <pre className="mt-1 max-w-xl overflow-x-auto rounded bg-neutral-50 p-2 text-xs text-text-secondary">{JSON.stringify(exception.detail, null, 2)}</pre>
        </div>
        <StatusBadge tone={exception.status === "open" ? "danger" : "success"} label={exception.status} />
      </div>
      {exception.status === "open" ? (
        <form action={formAction} noValidate className="flex flex-wrap items-end gap-2">
          <div className="w-72">
            <label htmlFor={`resolve-reason-${exception.id}`} className="sr-only">
              Resolution reason
            </label>
            <Input
              id={`resolve-reason-${exception.id}`}
              name="resolutionReason"
              type="text"
              required
              placeholder="Resolution reason (required)"
              invalid={Boolean(state.error)}
              aria-describedby={state.error ? `resolve-${exception.id}-error` : undefined}
            />
          </div>
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Resolving…" className="w-fit">
            Resolve
          </Button>
        </form>
      ) : (
        <p className="text-xs text-text-secondary">
          Resolved by {exception.resolvedBy ?? "—"}: {exception.resolutionReason ?? "—"}
        </p>
      )}
      <ErrorBanner id={`resolve-${exception.id}-error`} error={state.error} />
    </div>
  );
}

export function LoyaltyLiabilityReconciliationExceptionQueue({
  tenantSlug,
  entries,
}: {
  tenantSlug: string;
  entries: readonly { run: LoyaltyLiabilityReconciliationRun; exception: LoyaltyLiabilityReconciliationException }[];
}) {
  if (entries.length === 0) {
    return <EmptyState title="No open exceptions" description="Every reconciliation run's own exceptions have been resolved." />;
  }
  return (
    <div className="flex flex-col gap-3">
      {entries.map(({ run, exception }) => (
        <ExceptionRow key={exception.id} tenantSlug={tenantSlug} exception={exception} runCurrency={run.currency} />
      ))}
    </div>
  );
}
