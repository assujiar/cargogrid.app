"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { RoleActionState } from "./actions.ts";

const INITIAL_STATE: RoleActionState = { error: null };

export function CreateRolePanel({ createAction }: { createAction: (prevState: RoleActionState, formData: FormData) => Promise<RoleActionState> }) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);
  const describedBy = state.error ? "create-role-error" : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Create a new role</h2>
      <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <FormField id="name" label="Name">
          <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <div className="sm:col-span-2">
          <FormField id="description" label="Description (optional)">
            <Textarea id="description" name="description" rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>

        {state.error ? (
          <div className="col-span-full">
            <ValidationMessage id="create-role-error">{state.error}</ValidationMessage>
          </div>
        ) : null}

        <div className="col-span-full">
          <Button type="submit" loading={pending} loadingLabel="Creating…">
            Create role
          </Button>
        </div>
      </form>
    </section>
  );
}
