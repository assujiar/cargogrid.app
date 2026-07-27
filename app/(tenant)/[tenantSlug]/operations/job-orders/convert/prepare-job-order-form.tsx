"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { PrepareJobOrderState } from "./actions.ts";

const INITIAL_STATE: PrepareJobOrderState = { error: null };

/** Client Component wrapper (OPS-168) -- same `useActionState`/bound-action split every Commercial create-form already uses. */
export function PrepareJobOrderForm({ action }: { action: (prevState: PrepareJobOrderState, formData: FormData) => Promise<PrepareJobOrderState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <Button type="submit" loading={pending} loadingLabel="Converting…" className="w-fit">
        Convert to Job Order
      </Button>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
