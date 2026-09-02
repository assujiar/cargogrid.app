"use client";

/**
 * Cashback, Discount and Voucher admin client forms (CPL-319,
 * CG-S13-CPL-021). Same `useActionState`/bound-action split every prior
 * capability's own admin panel already uses.
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { DateInput } from "../../../../../components/forms/date-input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { formatLoyaltyBenefitValue, type LoyaltyBenefitEntitlement } from "../../../../../server/contracts/customer-portal-loyalty-benefits/customer-portal-loyalty-benefits.ts";
import type { LoyaltyAccount } from "../../../../../server/contracts/customer-portal-loyalty-program/customer-portal-loyalty-program.ts";
import {
  issueLoyaltyBenefitEntitlementAction,
  reverseLoyaltyBenefitEntitlementAction,
  holdLoyaltyBenefitEntitlementAction,
  releaseLoyaltyBenefitEntitlementHoldAction,
  expireLoyaltyBenefitEntitlementsAction,
  type LoyaltyBenefitsAdminFormState,
} from "./actions.ts";

const INITIAL_STATE: LoyaltyBenefitsAdminFormState = { error: null };

const STATUS_TONE: Record<LoyaltyBenefitEntitlement["status"], StatusTone> = {
  issued: "info",
  redeemed: "success",
  reversed: "neutral",
  expired: "neutral",
  held: "warning",
};

/** ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby` points at. */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return <ValidationMessage id={id}>{error}</ValidationMessage>;
}

export function ExpireBenefitsButton({ tenantSlug, programId }: { tenantSlug: string; programId: string }) {
  const [state, formAction, pending] = useActionState(expireLoyaltyBenefitEntitlementsAction.bind(null, tenantSlug, programId), INITIAL_STATE);
  return (
    <form action={formAction} noValidate>
      <ErrorBanner error={state.error} />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Scanning…">
        Run expiry scan
      </Button>
    </form>
  );
}

export function IssueBenefitForm({ tenantSlug, programId, account }: { tenantSlug: string; programId: string; account: LoyaltyAccount }) {
  const [state, formAction, pending] = useActionState(issueLoyaltyBenefitEntitlementAction.bind(null, tenantSlug, programId, account.id), INITIAL_STATE);
  // One IssueBenefitForm is rendered per loyalty account, so every id is scoped by account.id.
  // The RPC returns one error for the whole issue call, so all six fields point at it.
  const errorId = `issue-benefit-${account.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3" noValidate>
      <h4 className="text-xs font-semibold text-text-primary">Issue a benefit</h4>
      <div className="flex flex-wrap gap-2">
        <label htmlFor={`bt-${account.id}`} className="sr-only">
          Benefit type
        </label>
        <Select id={`bt-${account.id}`} name="benefitType" defaultValue="cashback" className="w-auto" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="cashback">Cashback</option>
          <option value="discount">Discount</option>
          <option value="voucher">Voucher</option>
        </Select>
        <label htmlFor={`ben-value-${account.id}`} className="sr-only">
          Value amount
        </label>
        <NumberInput
          id={`ben-value-${account.id}`}
          name="valueAmount"
          step="0.01"
          min="0.01"
          placeholder="Value amount"
          required
          className="w-32"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
        <label htmlFor={`ben-cap-${account.id}`} className="sr-only">
          Value cap (optional)
        </label>
        <NumberInput
          id={`ben-cap-${account.id}`}
          name="valueCap"
          step="0.01"
          min="0.01"
          placeholder="Value cap (optional)"
          className="w-40"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
        <label htmlFor={`ben-currency-${account.id}`} className="sr-only">
          Currency
        </label>
        <Input
          id={`ben-currency-${account.id}`}
          name="currency"
          type="text"
          defaultValue="USD"
          maxLength={3}
          placeholder="USD"
          required
          className="w-16 uppercase"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
        <label htmlFor={`ben-source-${account.id}`} className="sr-only">
          Source
        </label>
        <Input
          id={`ben-source-${account.id}`}
          name="sourceType"
          type="text"
          defaultValue="manual"
          placeholder="Source (e.g. manual)"
          required
          className="w-40"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
        <label htmlFor={`exp-${account.id}`} className="sr-only">
          Expiry (optional)
        </label>
        <DateInput id={`exp-${account.id}`} name="expiresAt" className="w-auto" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </div>
      <ErrorBanner id={errorId} error={state.error} />
      {state.rawCode ? (
        <p className="rounded-md bg-success/10 p-2 text-xs text-success">
          Voucher code (shown once, never recoverable): <span className="font-mono font-semibold">{state.rawCode}</span>
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Issuing…" className="w-fit">
        Issue benefit
      </Button>
    </form>
  );
}

export function EntitlementRow({ tenantSlug, programId, entitlement }: { tenantSlug: string; programId: string; entitlement: LoyaltyBenefitEntitlement }) {
  const [reverseState, reverseAction, reversePending] = useActionState(reverseLoyaltyBenefitEntitlementAction.bind(null, tenantSlug, programId, entitlement.id, entitlement.recordVersion), INITIAL_STATE);
  const [holdState, holdAction, holdPending] = useActionState(holdLoyaltyBenefitEntitlementAction.bind(null, tenantSlug, programId, entitlement.id), INITIAL_STATE);
  const [releaseState, releaseAction, releasePending] = useActionState(releaseLoyaltyBenefitEntitlementHoldAction.bind(null, tenantSlug, programId, entitlement.id), INITIAL_STATE);

  const canReverse = entitlement.status === "issued" || entitlement.status === "held" || entitlement.status === "redeemed";
  const canHold = entitlement.status === "issued";
  const canRelease = entitlement.status === "held";

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs font-medium text-text-secondary">{entitlement.benefitType}</p>
          <p className="text-sm font-semibold text-text-primary">{formatLoyaltyBenefitValue(entitlement)}</p>
          {entitlement.expiresAt ? <p className="text-xs text-text-secondary">Expires {new Date(entitlement.expiresAt).toLocaleDateString()}</p> : null}
        </div>
        <StatusBadge tone={STATUS_TONE[entitlement.status]} label={entitlement.status} />
      </div>

      <div className="flex flex-wrap items-end gap-3">
        {canHold ? (
          <form action={holdAction} className="flex items-end gap-2" noValidate>
            <label htmlFor={`hold-reason-${entitlement.id}`} className="sr-only">
              Hold reason
            </label>
            <Input
              id={`hold-reason-${entitlement.id}`}
              name="reason"
              placeholder="Hold reason (required)"
              required
              className="text-xs"
              invalid={Boolean(holdState.error)}
              aria-describedby={holdState.error ? `hold-${entitlement.id}-error` : undefined}
            />
            <ErrorBanner id={`hold-${entitlement.id}-error`} error={holdState.error} />
            <Button type="submit" variant="destructive" loading={holdPending} loadingLabel="Holding…" className="w-fit">
              Hold (fraud/dispute)
            </Button>
          </form>
        ) : null}
        {canRelease ? (
          <form action={releaseAction} noValidate>
            <ErrorBanner error={releaseState.error} />
            <Button type="submit" variant="secondary" loading={releasePending} loadingLabel="Releasing…" className="w-fit">
              Release hold
            </Button>
          </form>
        ) : null}
        {canReverse ? (
          <form action={reverseAction} className="flex items-end gap-2" noValidate>
            <label htmlFor={`reverse-reason-${entitlement.id}`} className="sr-only">
              Reversal reason
            </label>
            <Input
              id={`reverse-reason-${entitlement.id}`}
              name="reason"
              placeholder="Reversal reason (required)"
              required
              className="text-xs"
              invalid={Boolean(reverseState.error)}
              aria-describedby={reverseState.error ? `reverse-${entitlement.id}-error` : undefined}
            />
            <ErrorBanner id={`reverse-${entitlement.id}-error`} error={reverseState.error} />
            <Button type="submit" variant="secondary" loading={reversePending} loadingLabel="Reversing…" className="w-fit">
              Reverse
            </Button>
          </form>
        ) : null}
      </div>
    </div>
  );
}
