"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createContractFromQuotationAction, type CreateContractFromQuotationState } from "./actions.ts";
import { DateInput } from "../../../../../../components/forms/date-input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

const INITIAL_STATE: CreateContractFromQuotationState = { error: null };

/** COM-156's own main-flow entry point on the quotation page -- mirrors SendAcceptanceForm's (COM-154) useActionState pattern. Redirects to the new contract's own detail page on success (the action itself calls redirect(), never returned as state). */
export function CreateContractForm({ tenantSlug, quotationId }: { tenantSlug: string; quotationId: string }) {
  const [state, formAction, pending] = useActionState(
    async (prevState: CreateContractFromQuotationState, formData: FormData) => {
      const effectiveFrom = String(formData.get("effectiveFrom") ?? "");
      return createContractFromQuotationAction(tenantSlug, quotationId, effectiveFrom ? new Date(effectiveFrom).toISOString() : new Date().toISOString(), prevState, formData);
    },
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <FormField id="effectiveFrom" label="Effective from">
        <div className="w-48">
          <DateInput id="effectiveFrom" name="effectiveFrom" invalid={Boolean(state.error)} aria-describedby={state.error ? "create-contract-error" : undefined} />
        </div>
      </FormField>

      {state.error ? <ValidationMessage id="create-contract-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create contract
      </Button>
    </form>
  );
}
