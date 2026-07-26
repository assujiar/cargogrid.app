"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createContractRenewalAction } from "./actions.ts";

/** Renewal/amendment trigger (COM-156, Prompt 156's own alternative flow) -- copies this version's own price components into a new future-dated draft under the same root_contract_id; the mandatory reason and effective window are server-enforced (reason_required / customer_contracts_validity_check). */
export function RenewalForm({ tenantSlug, sourceContractId }: { tenantSlug: string; sourceContractId: string }) {
  const [effectiveFrom, setEffectiveFrom] = useState("");
  const [effectiveTo, setEffectiveTo] = useState("");
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Create renewal / amendment</h2>
      <p className="text-xs text-neutral-500">Copies this version&apos;s own price components into a new draft under the same contract -- edit the copy, then publish it once its effective window does not overlap another published version.</p>

      <div className="flex gap-2">
        <input type="date" value={effectiveFrom} onChange={(e) => setEffectiveFrom(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="date" value={effectiveTo} onChange={(e) => setEffectiveTo(e.target.value)} placeholder="Effective to (optional)" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <input placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <Button
        type="button"
        variant="secondary"
        disabled={!effectiveFrom || !reason.trim()}
        loading={pending}
        loadingLabel="Creating…"
        onClick={() =>
          startTransition(async () => {
            const result = await createContractRenewalAction(tenantSlug, sourceContractId, new Date(effectiveFrom).toISOString(), effectiveTo ? new Date(effectiveTo).toISOString() : null, reason.trim());
            if (result) setError(result.error);
          })
        }
      >
        Create renewal
      </Button>
    </div>
  );
}
