"use client";

import { useId, useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { decideCreditProfileApprovalStepAction } from "./credit-actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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
  // One instance renders per eligible step (credit-panel.tsx maps over
  // `myEligibleStepIds`), so the field ids must be per-instance, never a static string.
  const reactId = useId();
  const reasonId = `${reactId}-reason`;
  const errorId = `${reactId}-error`;

  function decide(decision: "approved" | "rejected") {
    startTransition(async () => {
      const result = await decideCreditProfileApprovalStepAction(tenantSlug, accountId, requestStepId, decision, reason.trim() || null, new Date().toISOString());
      setError(result.error);
    });
  }

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <p className="text-sm font-medium text-neutral-900">Step {stepOrder} is waiting on your decision</p>
      <FormField id={reasonId} label={<span className="sr-only">Reason (required to reject)</span>}>
        <Input
          id={reasonId}
          placeholder="Reason (required to reject)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          invalid={Boolean(error)}
          aria-describedby={error ? errorId : undefined}
        />
      </FormField>
      <Checkbox
        checked={reauthConfirmed}
        onChange={(e) => setReauthConfirmed(e.target.checked)}
        label="I have recently re-authenticated (required for this decision)"
        aria-describedby={error ? errorId : undefined}
      />
      {error ? <ValidationMessage id={errorId}>{error}</ValidationMessage> : null}
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
