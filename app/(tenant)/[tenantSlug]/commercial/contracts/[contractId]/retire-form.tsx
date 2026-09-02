"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { retireContractAction } from "./actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Retire trigger (COM-156) -- the governance-weighted, COM:Approve-gated, mandatory-reason transition off a published contract, mirroring app.revoke_quotation_acceptance_token/app.reject_rate_version's own "always requires a typed reason" pattern. */
export function RetireForm({ tenantSlug, contractId, expectedVersion }: { tenantSlug: string; contractId: string; expectedVersion: number }) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Retire this contract</h2>

      <FormField id="retire-reason" label={<span className="sr-only">Reason (required)</span>}>
        <Input id="retire-reason" placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} invalid={Boolean(error)} aria-describedby={error ? "retire-error" : undefined} />
      </FormField>

      {error ? <ValidationMessage id="retire-error">{error}</ValidationMessage> : null}

      <Button
        type="button"
        variant="destructive"
        disabled={!reason.trim()}
        loading={pending}
        loadingLabel="Retiring…"
        onClick={() =>
          startTransition(async () => {
            const result = await retireContractAction(tenantSlug, contractId, expectedVersion, reason.trim());
            if (result) setError(result.error);
          })
        }
      >
        Retire
      </Button>
    </div>
  );
}
