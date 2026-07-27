"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { DispatchBlocker } from "../../../../../server/contracts/basic-dispatch/basic-dispatch.ts";
import type { DispatchQueueFormState } from "./actions.ts";

const INITIAL_STATE: DispatchQueueFormState = { error: null };

/** One row's dispatch control -- disabled with its own blocker list when not ready, a single submit button (calling app.dispatch_shipment_order) when ready. */
export function DispatchRowAction({
  isReady,
  blockers,
  action,
}: {
  readonly isReady: boolean;
  readonly blockers: readonly DispatchBlocker[];
  readonly action: (prevState: DispatchQueueFormState, formData: FormData) => Promise<DispatchQueueFormState>;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  if (!isReady) {
    return (
      <ul className="text-xs text-neutral-500">
        {blockers.map((blocker) => (
          <li key={blocker.code}>{blocker.code}</li>
        ))}
      </ul>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <Button type="submit" loading={pending} loadingLabel="Dispatching…" className="w-fit">
        Dispatch
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
