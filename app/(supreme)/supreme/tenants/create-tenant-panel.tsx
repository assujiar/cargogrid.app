"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import type { CreateTenantActionState } from "./actions.ts";

const INITIAL_STATE: CreateTenantActionState = { error: null };

export function CreateTenantPanel({ createAction }: { createAction: (prevState: CreateTenantActionState, formData: FormData) => Promise<CreateTenantActionState> }) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);
  const describedBy = state.error ? "create-tenant-error" : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Create a new tenant</h2>
      <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <FormField id="slug" label="Slug">
          <Input id="slug" name="slug" type="text" pattern="[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="name" label="Name">
          <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>

        {state.error ? (
          <div className="col-span-full">
            <ValidationMessage id="create-tenant-error">{state.error}</ValidationMessage>
          </div>
        ) : null}

        <div className="col-span-full">
          <Button type="submit" loading={pending} loadingLabel="Creating…">
            Create tenant
          </Button>
        </div>
      </form>
    </section>
  );
}
