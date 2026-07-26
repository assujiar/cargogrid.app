"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { PrepareJobOrderHandoffState } from "./actions.ts";

const INITIAL_STATE: PrepareJobOrderHandoffState = { error: null };

/** Client Component wrapper (COM-160) -- same `useActionState`/bound-action split every prior Commercial create-form already uses. */
export function PrepareJobOrderHandoffForm({ action }: { action: (prevState: PrepareJobOrderHandoffState, formData: FormData) => Promise<PrepareJobOrderHandoffState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Preparing…">
        Prepare Job Order handoff
      </Button>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
