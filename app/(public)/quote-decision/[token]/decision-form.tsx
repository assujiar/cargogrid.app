"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { recordCustomerDecisionAction, type CustomerDecisionFormState } from "./actions.ts";

const INITIAL_STATE: CustomerDecisionFormState = { error: null, success: false };

/** COM-154: the one customer-facing decision form -- explicit accept/reject, never inferred from delivery or a page view (Prompt 154 §24: "delivery/read is not acceptance"). Rejecting requires a reason; accepting does not. */
export function DecisionForm({ rawToken }: { rawToken: string }) {
  const boundAction = recordCustomerDecisionAction.bind(null, rawToken);
  const [state, formAction, pending] = useActionState(boundAction, INITIAL_STATE);
  const [decision, setDecision] = useState<"accepted" | "rejected" | null>(null);

  if (state.success) {
    return (
      <div role="status" className="rounded-md border border-neutral-200 p-4 text-sm text-neutral-900">
        Thank you -- your decision has been recorded.
      </div>
    );
  }

  // ISS-2026-242: the action returns one error for the whole decision, not per-field ones.
  const describedBy = state.error ? "decision-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="decidedByName" label="Your name">
        <Input id="decidedByName" name="decidedByName" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="decidedByTitle" label="Title (optional)">
        <Input id="decidedByTitle" name="decidedByTitle" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="decidedByEmail" label="Email (optional)">
        <Input id="decidedByEmail" name="decidedByEmail" type="email" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      {decision === "rejected" ? (
        <FormField id="reason" label="Reason (required)">
          <Input id="reason" name="reason" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      ) : null}

      {state.error ? <ValidationMessage id="decision-error">{state.error}</ValidationMessage> : null}

      <div className="flex gap-2">
        <Button type="submit" name="decision" value="accepted" loading={pending && decision === "accepted"} loadingLabel="Accepting…" onClick={() => setDecision("accepted")}>
          Accept
        </Button>
        <Button type="submit" name="decision" value="rejected" variant="secondary" loading={pending && decision === "rejected"} loadingLabel="Rejecting…" onClick={() => setDecision("rejected")}>
          Reject
        </Button>
      </div>
    </form>
  );
}
