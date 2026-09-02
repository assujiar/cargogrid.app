"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { requestCreditProfileAction, type CreditFormState } from "./credit-actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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

  const describedBy = state.error ? "request-credit-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Request a credit profile</h2>
      <div className="flex gap-2">
        <div className="w-24">
          <FormField id="request-credit-currency" label={<span className="sr-only">Currency</span>}>
            <Input id="request-credit-currency" name="currency" type="text" defaultValue="IDR" maxLength={3} invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-48">
          <FormField id="request-credit-limit" label={<span className="sr-only">Requested limit</span>}>
            <NumberInput id="request-credit-limit" name="requestedLimitAmount" min={0} placeholder="Requested limit" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage id="request-credit-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Requesting…" className="w-fit">
        Request credit profile
      </Button>
    </form>
  );
}
