"use client";

/**
 * Cashback, Discount and Voucher customer-facing benefit wallet (CPL-319,
 * CG-S13-CPL-021). Same `useActionState`/bound-action split every prior
 * capability's own client form already uses.
 */

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { formatLoyaltyBenefitValue, describeLoyaltyBenefitExpiry, type CustomerPortalLoyaltyBenefitEntitlement } from "../../../../server/contracts/customer-portal-loyalty-benefits/customer-portal-loyalty-benefits.ts";
import { redeemLoyaltyBenefitEntitlementByIdAction, redeemLoyaltyBenefitEntitlementByCodeAction, type CustomerLoyaltyBenefitsFormState } from "./actions.ts";

const INITIAL_STATE: CustomerLoyaltyBenefitsFormState = { error: null };

const STATUS_TONE: Record<CustomerPortalLoyaltyBenefitEntitlement["status"], StatusTone> = {
  issued: "info",
  redeemed: "success",
  reversed: "neutral",
  expired: "neutral",
  held: "warning",
};

const BENEFIT_TYPE_LABEL: Record<CustomerPortalLoyaltyBenefitEntitlement["benefitType"], string> = {
  cashback: "Cashback",
  discount: "Discount",
  voucher: "Voucher",
};

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return <ValidationMessage>{error}</ValidationMessage>;
}

function BenefitCard({ tenantSlug, entitlement }: { tenantSlug: string; entitlement: CustomerPortalLoyaltyBenefitEntitlement }) {
  const [state, formAction, pending] = useActionState(redeemLoyaltyBenefitEntitlementByIdAction.bind(null, tenantSlug, entitlement.id, entitlement.recordVersion), INITIAL_STATE);
  const canRedeem = entitlement.benefitType === "voucher" && entitlement.status === "issued";
  const expiryText = describeLoyaltyBenefitExpiry(entitlement);

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <div>
          <p className="text-xs font-medium text-text-secondary">{BENEFIT_TYPE_LABEL[entitlement.benefitType]}</p>
          <p className="text-lg font-semibold text-text-primary">{formatLoyaltyBenefitValue(entitlement)}</p>
          <p className="text-xs text-text-secondary">{entitlement.programName}</p>
        </div>
        <StatusBadge tone={STATUS_TONE[entitlement.status]} label={entitlement.status} />
      </div>

      {entitlement.isOnHold ? <p className="rounded-md bg-warning/10 p-2 text-xs text-warning-strong">{entitlement.holdNotice}</p> : null}
      {expiryText ? <p className="text-xs text-text-secondary">{expiryText}</p> : null}

      {canRedeem ? (
        <form action={formAction} noValidate>
          <ErrorBanner error={state.error} />
          <Button type="submit" loading={pending} loadingLabel="Redeeming…" className="mt-1 w-fit">
            Redeem
          </Button>
        </form>
      ) : null}
    </div>
  );
}

function RedeemByCodeForm({ tenantSlug }: { tenantSlug: string }) {
  const [state, formAction, pending] = useActionState(redeemLoyaltyBenefitEntitlementByCodeAction.bind(null, tenantSlug), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-text-primary">Have a voucher code?</h3>
      <p className="text-xs text-text-secondary">Enter a voucher code you received elsewhere (e.g. by email) to redeem it here.</p>
      <div className="flex flex-wrap items-end gap-2">
        <FormField id="benefit-code" label={<span className="sr-only">Voucher code</span>} error={state.error ?? undefined}>
          <Input
            id="benefit-code"
            name="code"
            type="text"
            placeholder="CGV-XXXX-XXXX"
            required
            className="w-48 font-mono uppercase"
            invalid={Boolean(state.error)}
            aria-describedby={state.error ? "benefit-code-error" : undefined}
          />
        </FormField>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Redeeming…" className="w-fit">
          Redeem code
        </Button>
      </div>
    </form>
  );
}

export function CustomerLoyaltyBenefitsWallet({ tenantSlug, entitlements }: { tenantSlug: string; entitlements: readonly CustomerPortalLoyaltyBenefitEntitlement[] }) {
  return (
    <div className="flex flex-col gap-4">
      <RedeemByCodeForm tenantSlug={tenantSlug} />
      {entitlements.length === 0 ? (
        <EmptyState title="No cashback, discounts, or vouchers yet" description="Benefits issued to your account by your provider will appear here." />
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {entitlements.map((entitlement) => (
            <BenefitCard key={entitlement.id} tenantSlug={tenantSlug} entitlement={entitlement} />
          ))}
        </div>
      )}
    </div>
  );
}
