"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { retireContractAction } from "./actions.ts";

/** Retire trigger (COM-156) -- the governance-weighted, COM:Approve-gated, mandatory-reason transition off a published contract, mirroring app.revoke_quotation_acceptance_token/app.reject_rate_version's own "always requires a typed reason" pattern. */
export function RetireForm({ tenantSlug, contractId, expectedVersion }: { tenantSlug: string; contractId: string; expectedVersion: number }) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Retire this contract</h2>

      <input placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

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
