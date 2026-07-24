"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { checkCustomerCreditAction, type CheckCreditFormState } from "./credit-actions.ts";

const INITIAL_STATE: CheckCreditFormState = { error: null, result: null };

/** The deterministic, reproducible pre-conversion check (COM-157, Prompt 157 §20 task 3) -- the outcome (allow/blocked_*) is always shown, even to a viewer without COM:View selling price; the raw figures are masked per the RPC's own returned amountMasked flag. */
export function CreditCheckForm({ tenantSlug, accountId }: { tenantSlug: string; accountId: string }) {
  const [state, formAction, pending] = useActionState(
    async (prevState: CheckCreditFormState, formData: FormData) => {
      const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
      const requestedAmount = Number(formData.get("requestedAmount") ?? 0);
      return checkCustomerCreditAction(tenantSlug, accountId, currency, requestedAmount, prevState, formData);
    },
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <h3 className="text-sm font-semibold text-neutral-900">Check eligibility</h3>
      <div className="flex gap-2">
        <input name="currency" defaultValue="IDR" maxLength={3} className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input name="requestedAmount" type="number" min={0} placeholder="Transaction amount" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Checking…" className="w-fit">
        Run check
      </Button>

      {state.result ? (
        <div role="status" className="rounded-md border border-neutral-200 p-3 text-sm">
          <p className="font-medium text-neutral-900">Outcome: {state.result.outcome}</p>
          {!state.result.amountMasked ? (
            <p className="text-neutral-600">
              Effective limit: {state.result.effectiveLimitAmount ?? "—"} {state.result.currency}
            </p>
          ) : (
            <p className="text-neutral-600">Restricted</p>
          )}
        </div>
      ) : null}
    </form>
  );
}
