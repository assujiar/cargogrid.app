"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { createSupportQueueAction, type SupremeHelpdeskActionState } from "./actions.ts";

const INITIAL_STATE: SupremeHelpdeskActionState = { error: null };

export function CreateSupportQueueForm() {
  const [state, formAction, pending] = useActionState(createSupportQueueAction, INITIAL_STATE);
  // ISS-2026-242: one error covers the whole create call, so all three fields point at it.
  const describedBy = state.error ? "create-support-queue-error" : undefined;

  return (
    <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2">
      <div className="w-32">
        <FormField id="sq-code" label="Code">
          <Input id="sq-code" name="code" required minLength={1} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="w-48">
        <FormField id="sq-name" label="Name">
          <Input id="sq-name" name="name" required minLength={1} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="w-56">
        <FormField id="sq-description" label="Description (optional)">
          <Input id="sq-description" name="description" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        Add queue
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="create-support-queue-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}
