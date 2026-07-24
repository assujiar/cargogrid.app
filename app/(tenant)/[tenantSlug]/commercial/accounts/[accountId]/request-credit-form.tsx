"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { requestCreditProfileAction, type CreditFormState } from "./credit-actions.ts";

const INITIAL_STATE: CreditFormState = { error: null };

/** COM-157: the main flow's own entry point -- unconditionally routes through the Platform Approval Engine (no auto-approve path exists for credit). */
export function RequestCreditForm({ tenantSlug, accountId }: { tenantSlug: string; accountId: string }) {
  const [state, formAction, pending] = useActionState(
    async (prevState: CreditFormState, formData: FormData) => {
      const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
      const requestedLimitAmount = Number(formData.get("requestedLimitAmount") ?? 0);
      return requestCreditProfileAction(tenantSlug, accountId, currency, requestedLimitAmount, prevState, formData);
    },
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Request a credit profile</h2>
      <div className="flex gap-2">
        <input name="currency" defaultValue="IDR" maxLength={3} className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input name="requestedLimitAmount" type="number" min={0} placeholder="Requested limit" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Requesting…" className="w-fit">
        Request credit profile
      </Button>
    </form>
  );
}
