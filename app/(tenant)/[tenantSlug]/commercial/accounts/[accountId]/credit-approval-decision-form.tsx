"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { decideCreditProfileApprovalStepAction } from "./credit-actions.ts";

/**
 * One eligible step's decide form (COM-157) -- mirrors ApprovalDecisionForm (COM-153)
 * plus the reauth-freshness checkbox Prompt 157 §16 requires for a privileged approver
 * action. No live MFA challenge UI exists yet anywhere in this repository (the migration's
 * own disclosed boundary) -- checking the box captures the current timestamp as the
 * caller's own attestation, which the server independently re-validates for freshness
 * (<=5 minutes) on every call, never trusted blindly.
 */
export function CreditApprovalDecisionForm({ tenantSlug, accountId, requestStepId, stepOrder }: { tenantSlug: string; accountId: string; requestStepId: string; stepOrder: number }) {
  const [reason, setReason] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function decide(decision: "approved" | "rejected") {
    startTransition(async () => {
      const result = await decideCreditProfileApprovalStepAction(tenantSlug, accountId, requestStepId, decision, reason.trim() || null, new Date().toISOString());
      setError(result.error);
    });
  }

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <p className="text-sm font-medium text-neutral-900">Step {stepOrder} is waiting on your decision</p>
      <input placeholder="Reason (required to reject)" value={reason} onChange={(e) => setReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      <label className="flex items-center gap-2 text-xs text-neutral-600">
        <input type="checkbox" checked={reauthConfirmed} onChange={(e) => setReauthConfirmed(e.target.checked)} />
        I have recently re-authenticated (required for this decision)
      </label>
      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}
      <div className="flex gap-2">
        <Button type="button" disabled={!reauthConfirmed} loading={pending} loadingLabel="Approving…" onClick={() => decide("approved")}>
          Approve
        </Button>
        <Button type="button" variant="secondary" disabled={!reauthConfirmed || !reason.trim()} loading={pending} loadingLabel="Rejecting…" onClick={() => decide("rejected")}>
          Reject
        </Button>
      </div>
    </div>
  );
}
