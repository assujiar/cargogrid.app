"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { DispatchBlocker } from "../../../../../server/contracts/basic-dispatch/basic-dispatch.ts";
import type { DispatchBoardFormState } from "./actions.ts";

const INITIAL_STATE: DispatchBoardFormState = { error: null };

/** One row's dispatch control -- only meaningful for an assigned row (isReady non-null); dispatched/in_transit rows render nothing here (readiness/dispatch no longer apply). */
export function DispatchBoardRowAction({
  isReady,
  blockers,
  action,
}: {
  readonly isReady: boolean | null;
  readonly blockers: readonly DispatchBlocker[] | null;
  readonly action: (prevState: DispatchBoardFormState, formData: FormData) => Promise<DispatchBoardFormState>;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  if (isReady === null) {
    return <span className="text-xs text-neutral-500">—</span>;
  }

  if (!isReady) {
    return (
      <ul className="text-xs text-neutral-500">
        {(blockers ?? []).map((blocker) => (
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
