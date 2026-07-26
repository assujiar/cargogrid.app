"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
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

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <div className="flex flex-col gap-1">
        <label htmlFor="decidedByName" className="text-sm font-medium text-neutral-700">
          Your name
        </label>
        <input id="decidedByName" name="decidedByName" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="decidedByTitle" className="text-sm font-medium text-neutral-700">
          Title (optional)
        </label>
        <input id="decidedByTitle" name="decidedByTitle" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="decidedByEmail" className="text-sm font-medium text-neutral-700">
          Email (optional)
        </label>
        <input id="decidedByEmail" name="decidedByEmail" type="email" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {decision === "rejected" ? (
        <div className="flex flex-col gap-1">
          <label htmlFor="reason" className="text-sm font-medium text-neutral-700">
            Reason (required)
          </label>
          <input id="reason" name="reason" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      ) : null}

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

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
