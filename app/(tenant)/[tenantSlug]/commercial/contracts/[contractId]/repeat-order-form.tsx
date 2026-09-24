"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { repeatContractAsQuotationAction } from "./actions.ts";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/**
 * CG-AUDIT-2026-09-02 E1 (repeat-order bounded core): the practical "place a
 * repeat order under this contract" entry point -- clones the contract's own
 * originating quotation into a brand-new draft (same customer/lines/terms),
 * which still goes through the ordinary submit/accept/convert/handoff chain
 * before ever becoming a job order.
 */
export function RepeatOrderForm({ tenantSlug, sourceQuotationId }: { tenantSlug: string; sourceQuotationId: string }) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Repeat as new quotation</h2>
      <p className="text-xs text-neutral-500">Creates a new draft quotation with the same customer, lines, and terms as this contract&apos;s own originating quotation -- edit and submit it like any other quotation.</p>

      {error ? <ValidationMessage id="repeat-order-error">{error}</ValidationMessage> : null}

      <Button
        type="button"
        variant="secondary"
        loading={pending}
        loadingLabel="Creating…"
        onClick={() =>
          startTransition(async () => {
            const result = await repeatContractAsQuotationAction(tenantSlug, sourceQuotationId);
            if (result) setError(result.error);
          })
        }
      >
        Repeat as new quotation
      </Button>
    </div>
  );
}
