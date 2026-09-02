"use client";

import { useId, useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { decideQuotationApprovalStepAction } from "./actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** One eligible step's decide form (COM-153) -- approve needs no reason; reject/request-revision shares the same "rejected" decision with a reason, matching this capability's own disclosed "request revision is not a third verb" scope (server/mutations/quotation-approval.ts). */
export function ApprovalDecisionForm({ tenantSlug, quotationId, requestStepId, stepOrder }: { tenantSlug: string; quotationId: string; requestStepId: string; stepOrder: number }) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  // One instance renders per eligible step (approval-panel.tsx maps over the eligible
  // step ids), so the field ids must be per-instance, never a static string.
  const reactId = useId();
  const reasonId = `${reactId}-reason`;
  const errorId = `${reactId}-error`;

  function decide(decision: "approved" | "rejected") {
    startTransition(async () => {
      const result = await decideQuotationApprovalStepAction(tenantSlug, quotationId, requestStepId, decision, reason.trim() || null);
      setError(result.error);
    });
  }

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <p className="text-sm font-medium text-neutral-900">Step {stepOrder} is waiting on your decision</p>
      <FormField id={reasonId} label={<span className="sr-only">Reason (required to reject or request revision)</span>}>
        <Input
          id={reasonId}
          placeholder="Reason (required to reject or request revision)"
          value={reason}
          onChange={(e) => setReason(e.target.value)}
          invalid={Boolean(error)}
          aria-describedby={error ? errorId : undefined}
        />
      </FormField>
      {error ? <ValidationMessage id={errorId}>{error}</ValidationMessage> : null}
      <div className="flex gap-2">
        <Button type="button" loading={pending} loadingLabel="Approving…" onClick={() => decide("approved")}>
          Approve
        </Button>
        <Button type="button" variant="secondary" disabled={!reason.trim()} loading={pending} loadingLabel="Rejecting…" onClick={() => decide("rejected")}>
          Reject / request revision
        </Button>
      </div>
    </div>
  );
}
