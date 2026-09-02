"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { ContactFormState } from "./actions.ts";
import { Input } from "../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";

const INITIAL_STATE: ContactFormState = { error: null };

/** Client Component wrapper (COM-145) -- mirrors COM-143's own `capture-lead-form.tsx` split (Server Component page, Client Component form). */
export function CreateContactForm({ action }: { action: (prevState: ContactFormState, formData: FormData) => Promise<ContactFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  const describedBy = state.error ? "create-contact-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Add a contact</h2>

      <FormField id="fullName" label="Full name">
        <Input id="fullName" name="fullName" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField
        id="title"
        label={
          <>
            Title <span className="font-normal text-neutral-500">(optional)</span>
          </>
        }
      >
        <Input id="title" name="title" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="email" label="Email">
        <Input id="email" name="email" type="email" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="phone" label="Phone">
        <Input id="phone" name="phone" type="tel" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      {state.error ? <ValidationMessage id="create-contact-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Adding…">
        Add contact
      </Button>
    </form>
  );
}
