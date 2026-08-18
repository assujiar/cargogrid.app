"use client";

/**
 * Cashback, Discount and Voucher admin client forms (CPL-319,
 * CG-S13-CPL-021). Same `useActionState`/bound-action split every prior
 * capability's own admin panel already uses.
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return (
    <p role="alert" className="text-sm text-danger">
      {error}
    </p>
  );
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
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3" noValidate>
      <h4 className="text-xs font-semibold text-text-primary">Issue a benefit</h4>
      <div className="flex flex-wrap gap-2">
        <label htmlFor={`bt-${account.id}`} className="sr-only">
          Benefit type
        </label>
        <select id={`bt-${account.id}`} name="benefitType" defaultValue="cashback" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm">
          <option value="cashback">Cashback</option>
          <option value="discount">Discount</option>
          <option value="voucher">Voucher</option>
        </select>
        <input name="valueAmount" type="number" step="0.01" min="0.01" placeholder="Value amount" required className="w-32 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
        <input name="valueCap" type="number" step="0.01" min="0.01" placeholder="Value cap (optional)" className="w-40 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
        <input name="currency" type="text" defaultValue="USD" maxLength={3} placeholder="USD" required className="w-16 rounded-md border border-neutral-300 px-2 py-1.5 text-sm uppercase" />
        <input name="sourceType" type="text" defaultValue="manual" placeholder="Source (e.g. manual)" required className="w-40 rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
        <label htmlFor={`exp-${account.id}`} className="sr-only">
          Expiry (optional)
        </label>
        <input id={`exp-${account.id}`} name="expiresAt" type="date" className="rounded-md border border-neutral-300 px-2 py-1.5 text-sm" />
      </div>
      <ErrorBanner error={state.error} />
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
            <input name="reason" placeholder="Hold reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
            <ErrorBanner error={holdState.error} />
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
            <input name="reason" placeholder="Reversal reason (required)" required className="rounded-md border border-neutral-300 px-2 py-1 text-xs" />
            <ErrorBanner error={reverseState.error} />
            <Button type="submit" variant="secondary" loading={reversePending} loadingLabel="Reversing…" className="w-fit">
              Reverse
            </Button>
          </form>
        ) : null}
      </div>
    </div>
  );
}
