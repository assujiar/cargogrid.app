"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { LeadFormState } from "./actions.ts";
import { Input } from "../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";

const INITIAL_STATE: LeadFormState = { error: null };

/** Client Component wrapper (COM-143) -- the Lead List page itself stays a Server Component (server-paginated fetch); only this bounded form needs `useActionState`'s pending/error state, the same split `app/(public)/login/page.tsx` established. */
export function CaptureLeadForm({ action }: { action: (prevState: LeadFormState, formData: FormData) => Promise<LeadFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  const describedBy = state.error ? "capture-lead-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Capture a lead</h2>

      <FormField id="contactName" label="Contact name">
        <Input id="contactName" name="contactName" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField
        id="companyName"
        label={
          <>
            Company <span className="font-normal text-neutral-500">(optional)</span>
          </>
        }
      >
        <Input id="companyName" name="companyName" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField
        id="email"
        label={
          <>
            Email <span className="font-normal text-neutral-500">(one of email/phone required)</span>
          </>
        }
      >
        <Input id="email" name="email" type="email" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="phone" label="Phone">
        <Input id="phone" name="phone" type="tel" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      {state.error ? <ValidationMessage id="capture-lead-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Capturing…">
        Capture lead
      </Button>
    </form>
  );
}
