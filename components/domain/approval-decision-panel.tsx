"use client";

/**
 * Approval Decision Panel (`docs/design-system/04_DATA_EXPERIENCE_AND_WORKFLOW_
 * PATTERNS.md` §2 "Approve / Reject / Reopen / Cancel... renders through the Approval
 * Decision Panel pattern... not yet built"). Generic, business-logic-free: the caller
 * supplies `onApprove`/`onReject`, this component only owns the reason-textarea +
 * confirm-button UI and the "reject requires a reason" rule
 * (`04_DATA_EXPERIENCE_AND_WORKFLOW_PATTERNS.md` §2's binding rule, restated here).
 *
 * Not yet wired into `approval-decision-form.tsx`/`credit-approval-decision-form.tsx`
 * (`docs/design-system/08_COMPONENT_INVENTORY.md` §4's migration-map entry) -- that
 * remains a distinct, Medium-risk follow-up since it touches two real, tested submit
 * paths, not a display-only change.
 */

import { useState } from "react";
import { Button } from "../ui/button.tsx";
import { Textarea } from "../forms/textarea.tsx";
import { FormField } from "../forms/form-field.tsx";

export interface ApprovalDecisionPanelProps {
  readonly onApprove: (reason: string) => void;
  readonly onReject: (reason: string) => void;
  readonly approveLabel?: string;
  readonly rejectLabel?: string;
  readonly disabled?: boolean;
  readonly loading?: boolean;
}

export function ApprovalDecisionPanel({
  onApprove,
  onReject,
  approveLabel = "Approve",
  rejectLabel = "Reject",
  disabled = false,
  loading = false,
}: ApprovalDecisionPanelProps) {
  const [reason, setReason] = useState("");
  const [rejectError, setRejectError] = useState<string | undefined>(undefined);

  function handleReject() {
    if (reason.trim() === "") {
      setRejectError("A reason is required to reject.");
      return;
    }
    setRejectError(undefined);
    onReject(reason);
  }

  return (
    <div className="flex flex-col gap-3">
      <FormField id="approval-decision-reason" label="Reason" helpText="Required to reject; optional to approve." error={rejectError}>
        <Textarea
          id="approval-decision-reason"
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          disabled={disabled || loading}
        />
      </FormField>
      <div className="flex gap-2">
        <Button variant="primary" disabled={disabled} loading={loading} onClick={() => onApprove(reason)}>
          {approveLabel}
        </Button>
        <Button variant="destructive" disabled={disabled} loading={loading} onClick={handleReject}>
          {rejectLabel}
        </Button>
      </div>
    </div>
  );
}
