"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { OpportunityFormState } from "./actions.ts";
import { Input } from "../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";

const INITIAL_STATE: OpportunityFormState = { error: null };

/** Client Component wrapper (COM-147) -- same `useActionState`/bound-action split `capture-lead-form.tsx` (COM-143) already established. */
export function CreateOpportunityForm({ action }: { action: (prevState: OpportunityFormState, formData: FormData) => Promise<OpportunityFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  const describedBy = state.error ? "create-opportunity-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create an opportunity</h2>

      <FormField id="prospectId" label="Prospect ID">
        <Input id="prospectId" name="prospectId" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="name" label="Opportunity name">
        <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      {state.error ? <ValidationMessage id="create-opportunity-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create opportunity
      </Button>
    </form>
  );
}
