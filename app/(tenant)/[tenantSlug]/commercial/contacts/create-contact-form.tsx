"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { ContactFormState } from "./actions.ts";

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
        <input id="fullName" name="fullName" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="title" className="text-sm font-medium text-neutral-700">
          Title <span className="font-normal text-neutral-500">(optional)</span>
        </label>
        <input id="title" name="title" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="email" className="text-sm font-medium text-neutral-700">
          Email
        </label>
        <input id="email" name="email" type="email" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="phone" className="text-sm font-medium text-neutral-700">
          Phone
        </label>
        <input id="phone" name="phone" type="tel" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
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
