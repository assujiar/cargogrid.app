"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import type { CancelReportRunFormState } from "./actions.ts";

const INITIAL_STATE: CancelReportRunFormState = { error: null, success: false };

/** Client Component wrapper (IAE-002) -- same `useActionState`/bound-action split every prior report action form already uses. Only rendered for a run this actor may plausibly cancel (queued status); the server action still re-checks requester/COM:Export/Supreme authority for real, this is not the enforcement point. */
export function CancelRunButton({ action }: { action: (prevState: CancelReportRunFormState, formData: FormData) => Promise<CancelReportRunFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  if (state.success) {
    return <span className="text-xs text-neutral-500">Cancelled</span>;
  }

  return (
    <form action={formAction} className="flex flex-col items-start gap-1" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Cancelling…">
        Cancel
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
