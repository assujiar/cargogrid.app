"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createQuotationDraftAction } from "../actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Quotation-draft trigger (COM-151) -- currency/validity only; the contact and every selling line are added on the quotation's own builder page after creation. */
export function CreateQuotationForm({ tenantSlug, opportunityId, defaultCurrency }: { tenantSlug: string; opportunityId: string; defaultCurrency: string | null }) {
  const [currency, setCurrency] = useState(defaultCurrency ?? "");
  const [validityTo, setValidityTo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const describedBy = error ? "create-quotation-error" : undefined;
  const invalid = Boolean(error);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Create quotation</h2>

      <div className="flex gap-2">
        <div className="w-32">
          <FormField id="create-quotation-currency" label={<span className="sr-only">Currency</span>}>
            <Input
              id="create-quotation-currency"
              placeholder="Currency (e.g. IDR)"
              value={currency}
              onChange={(e) => setCurrency(e.target.value.toUpperCase())}
              invalid={invalid}
              aria-describedby={describedBy}
            />
          </FormField>
        </div>
        <FormField id="create-quotation-validity-to" label={<span className="sr-only">Valid until</span>}>
          <Input id="create-quotation-validity-to" type="datetime-local" value={validityTo} onChange={(e) => setValidityTo(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
        </FormField>
      </div>

      {error ? <ValidationMessage id="create-quotation-error">{error}</ValidationMessage> : null}

      <Button
        type="button"
        disabled={!/^[A-Z]{3}$/.test(currency) || !validityTo}
        loading={pending}
        loadingLabel="Creating…"
        onClick={() =>
          startTransition(async () => {
            const result = await createQuotationDraftAction(tenantSlug, opportunityId, currency, new Date(validityTo).toISOString());
            setError(result.error);
          })
        }
      >
        Create quotation draft
      </Button>
    </div>
  );
}
