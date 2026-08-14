"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { createSupportQueueAction, type SupremeHelpdeskActionState } from "./actions.ts";

const INITIAL_STATE: SupremeHelpdeskActionState = { error: null };

export function CreateSupportQueueForm() {
  const [state, formAction, pending] = useActionState(createSupportQueueAction, INITIAL_STATE);

  return (
    <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2">
      <label className="text-xs text-neutral-500">
        Code
        <input name="code" required minLength={1} className="mt-1 w-32 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Name
        <input name="name" required minLength={1} className="mt-1 w-48 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Description (optional)
        <input name="description" className="mt-1 w-56 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        Add queue
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
