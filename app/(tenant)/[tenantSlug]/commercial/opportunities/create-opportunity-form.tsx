"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { OpportunityFormState } from "./actions.ts";

const INITIAL_STATE: OpportunityFormState = { error: null };

/** Client Component wrapper (COM-147) -- same `useActionState`/bound-action split `capture-lead-form.tsx` (COM-143) already established. */
export function CreateOpportunityForm({ action }: { action: (prevState: OpportunityFormState, formData: FormData) => Promise<OpportunityFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create an opportunity</h2>

      <div className="flex flex-col gap-1">
        <label htmlFor="prospectId" className="text-sm font-medium text-neutral-700">
          Prospect ID
        </label>
        <input id="prospectId" name="prospectId" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="name" className="text-sm font-medium text-neutral-700">
          Opportunity name
        </label>
        <input id="name" name="name" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create opportunity
      </Button>
    </form>
  );
}
