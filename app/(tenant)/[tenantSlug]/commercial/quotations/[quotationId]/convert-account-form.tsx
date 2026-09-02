"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { convertQuotationToAccountAction, type ConvertQuotationToAccountState } from "./actions.ts";
import type { Account } from "../../../../../../server/contracts/account/account.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Radio } from "../../../../../../components/forms/radio.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

const INITIAL_STATE: ConvertQuotationToAccountState = { error: null, accountId: null };

/** COM-155: one action, two shapes -- "create a new account" (no selection) or "link to an existing one" (radio-selected from the duplicate candidates surfaced by app.get_account_conversion_readiness), the same "one mechanism, choice narrows behavior" precedent SendAcceptanceForm (COM-154) already established. */
export function ConvertAccountForm({
  tenantSlug,
  quotationId,
  duplicateCandidates,
}: {
  tenantSlug: string;
  quotationId: string;
  duplicateCandidates: readonly Account[];
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: ConvertQuotationToAccountState, formData: FormData) => {
      const targetAccountId = String(formData.get("targetAccountId") ?? "").trim() || null;
      const parentAccountId = String(formData.get("parentAccountId") ?? "").trim() || null;
      return convertQuotationToAccountAction(tenantSlug, quotationId, targetAccountId, parentAccountId, prevState, formData);
    },
    INITIAL_STATE,
  );

  const describedBy = state.error ? "convert-account-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      {duplicateCandidates.length > 0 ? (
        <div className="flex flex-col gap-1">
          <span className="text-sm font-medium text-neutral-700">Possible existing match</span>
          <p className="text-xs text-neutral-500">This customer&apos;s legal identity may already exist. Choose one to link instead of creating a duplicate, or leave unselected to create a new account.</p>
          <div className="flex flex-col gap-1">
            <Radio name="targetAccountId" value="" defaultChecked label="Create a new account" aria-describedby={describedBy} />
            {duplicateCandidates.map((candidate) => (
              <Radio
                key={candidate.id}
                name="targetAccountId"
                value={candidate.id}
                label={`${candidate.legalName}${candidate.taxId ? ` (${candidate.taxId})` : ""}`}
                aria-describedby={describedBy}
              />
            ))}
          </div>
        </div>
      ) : null}

      <FormField id="parentAccountId" label="Parent account ID (optional)">
        <div className="w-96">
          <Input
            id="parentAccountId"
            name="parentAccountId"
            type="text"
            placeholder="Only used when creating a new account"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </div>
      </FormField>

      {state.error ? <ValidationMessage id="convert-account-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Converting…" className="w-fit">
        Convert to account
      </Button>
    </form>
  );
}
