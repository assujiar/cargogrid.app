"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import type { SupportAccessGrant } from "../../../../server/contracts/support-access/support-access.ts";
import type { SupportAccessActionState } from "./actions.ts";

const INITIAL_STATE: SupportAccessActionState = { error: null };

type BoundAction = (prevState: SupportAccessActionState, formData: FormData) => Promise<SupportAccessActionState>;

function ApproveForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Approving…" className="w-fit">
        Approve
      </Button>
    </form>
  );
}

function ReasonForm({
  action,
  submitLabel,
  pendingLabel,
  fieldName = "reason",
  variant = "secondary",
}: {
  action: BoundAction;
  submitLabel: string;
  pendingLabel: string;
  fieldName?: string;
  variant?: "secondary" | "destructive";
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const fieldId = `${fieldName}-${submitLabel.toLowerCase().replace(/\s+/g, "-")}`;
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <label htmlFor={fieldId} className="sr-only">
        {submitLabel} reason
      </label>
      <Input id={fieldId} name={fieldName} type="text" placeholder={fieldName === "note" ? "Post-review note" : "Reason"} required className="w-48 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={pendingLabel} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

/**
 * CG-AUDIT-2026-09-02 UNTRACKED-D4: the one action cell per grant row, varying by the
 * grant's own current status -- never a "Start/end session" control (see actions.ts's own
 * header for why that stays out of scope).
 */
export function GrantActionsCell({
  grant,
  approveAction,
  denyAction,
  revokeAction,
  completePostReviewAction,
}: {
  grant: SupportAccessGrant;
  approveAction: BoundAction;
  denyAction: BoundAction;
  revokeAction: BoundAction;
  completePostReviewAction: BoundAction;
}) {
  if (grant.status === "pending_approval") {
    return (
      <div className="flex flex-col gap-2">
        <ApproveForm action={approveAction} />
        <ReasonForm action={denyAction} submitLabel="Deny" pendingLabel="Denying…" variant="destructive" />
      </div>
    );
  }

  if (grant.status === "approved" && grant.revokedAt === null) {
    const needsPostReview = grant.emergency && grant.postReviewCompletedAt === null;
    return (
      <div className="flex flex-col gap-2">
        <ReasonForm action={revokeAction} submitLabel="Revoke" pendingLabel="Revoking…" variant="destructive" />
        {needsPostReview ? <ReasonForm action={completePostReviewAction} submitLabel="Complete post-review" pendingLabel="Saving…" fieldName="note" /> : null}
      </div>
    );
  }

  return <span className="text-xs text-neutral-500">—</span>;
}
