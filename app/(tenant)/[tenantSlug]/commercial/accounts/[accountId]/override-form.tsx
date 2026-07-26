"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createCreditOverrideAction } from "./credit-actions.ts";

/** Bounded, reasoned, always-expiring override (COM-157, Prompt 157 §22's alternative flow) -- COM:Approve + reauth-freshness gated ("elevated approval"). */
export function OverrideForm({ tenantSlug, accountId, profileId }: { tenantSlug: string; accountId: string; profileId: string }) {
  const [amount, setAmount] = useState("");
  const [reason, setReason] = useState("");
  const [expiresAt, setExpiresAt] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <h3 className="text-sm font-semibold text-neutral-900">Create a bounded override</h3>
      <div className="flex gap-2">
        <input type="number" min={0} placeholder="Override amount" value={amount} onChange={(e) => setAmount(e.target.value)} className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="datetime-local" value={expiresAt} onChange={(e) => setExpiresAt(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>
      <input placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label className="flex items-center gap-2 text-xs text-neutral-600">
        <input type="checkbox" checked={reauthConfirmed} onChange={(e) => setReauthConfirmed(e.target.checked)} />
        I have recently re-authenticated (required for this action)
      </label>
      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}
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
