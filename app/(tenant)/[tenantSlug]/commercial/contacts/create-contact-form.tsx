"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { ContactFormState } from "./actions.ts";
import { Input } from "../../../../../components/forms/input.tsx";

const INITIAL_STATE: ContactFormState = { error: null };

/** Client Component wrapper (COM-145) -- mirrors COM-143's own `capture-lead-form.tsx` split (Server Component page, Client Component form). */
export function CreateContactForm({ action }: { action: (prevState: ContactFormState, formData: FormData) => Promise<ContactFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Add a contact</h2>

      <div className="flex flex-col gap-1">
        <label htmlFor="fullName" className="text-sm font-medium text-neutral-700">
          Full name
        </label>
        <Input id="fullName" name="fullName" type="text" required />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="title" className="text-sm font-medium text-neutral-700">
          Title <span className="font-normal text-neutral-500">(optional)</span>
        </label>
        <Input id="title" name="title" type="text" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="email" className="text-sm font-medium text-neutral-700">
          Email
        </label>
        <Input id="email" name="email" type="email" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="phone" className="text-sm font-medium text-neutral-700">
          Phone
        </label>
        <Input id="phone" name="phone" type="tel" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Adding…">
        Add contact
      </Button>
    </form>
  );
}
