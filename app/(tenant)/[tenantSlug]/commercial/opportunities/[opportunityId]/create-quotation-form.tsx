"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createQuotationDraftAction } from "../actions.ts";

/** Quotation-draft trigger (COM-151) -- currency/validity only; the contact and every selling line are added on the quotation's own builder page after creation. */
export function CreateQuotationForm({ tenantSlug, opportunityId, defaultCurrency }: { tenantSlug: string; opportunityId: string; defaultCurrency: string | null }) {
  const [currency, setCurrency] = useState(defaultCurrency ?? "");
  const [validityTo, setValidityTo] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Create quotation</h2>

      <div className="flex gap-2">
        <input
          placeholder="Currency (e.g. IDR)"
          value={currency}
          onChange={(e) => setCurrency(e.target.value.toUpperCase())}
          className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
        <input type="datetime-local" value={validityTo} onChange={(e) => setValidityTo(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

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
