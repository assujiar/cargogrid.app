"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createCreditOverrideAction } from "./credit-actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Bounded, reasoned, always-expiring override (COM-157, Prompt 157 §22's alternative flow) -- COM:Approve + reauth-freshness gated ("elevated approval"). */
export function OverrideForm({ tenantSlug, accountId, profileId }: { tenantSlug: string; accountId: string; profileId: string }) {
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const describedBy = error ? "override-error" : undefined;

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <h3 className="text-sm font-semibold text-neutral-900">Create a bounded override</h3>
      <div className="flex gap-2">
        <div className="w-40">
          <FormField id="override-amount" label={<span className="sr-only">Override amount</span>}>
            <NumberInput id="override-amount" min={0} placeholder="Override amount" value={amount} onChange={(e) => setAmount(e.target.value)} invalid={Boolean(error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <FormField id="override-expires-at" label={<span className="sr-only">Expires at</span>}>
          <Input id="override-expires-at" type="datetime-local" value={expiresAt} onChange={(e) => setExpiresAt(e.target.value)} invalid={Boolean(error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id="override-reason" label={<span className="sr-only">Reason (required)</span>}>
        <Input id="override-reason" placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} invalid={Boolean(error)} aria-describedby={describedBy} />
      </FormField>
      <Checkbox
        checked={reauthConfirmed}
        onChange={(e) => setReauthConfirmed(e.target.checked)}
        label="I have recently re-authenticated (required for this action)"
        aria-describedby={describedBy}
      />
      {error ? <ValidationMessage id="override-error">{error}</ValidationMessage> : null}
      <Button
        type="button"
        variant="secondary"
        disabled={!reauthConfirmed || !amount.trim() || !reason.trim() || !expiresAt}
        loading={pending}
        loadingLabel="Creating…"
        className="w-fit"
        onClick={() =>
          startTransition(async () => {
            const result = await createCreditOverrideAction(tenantSlug, accountId, profileId, Number(amount) || 0, reason.trim(), new Date(expiresAt).toISOString(), new Date().toISOString());
            setError(result.error);
          })
        }
      >
        Create override
      </Button>
    </div>
  );
}
