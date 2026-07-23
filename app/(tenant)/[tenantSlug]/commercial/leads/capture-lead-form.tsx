"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { LeadFormState } from "./actions.ts";

const INITIAL_STATE: LeadFormState = { error: null };

/** Client Component wrapper (COM-143) -- the Lead List page itself stays a Server Component (server-paginated fetch); only this bounded form needs `useActionState`'s pending/error state, the same split `app/(public)/login/page.tsx` established. */
export function CaptureLeadForm({ action }: { action: (prevState: LeadFormState, formData: FormData) => Promise<LeadFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Capture a lead</h2>

      <div className="flex flex-col gap-1">
        <label htmlFor="contactName" className="text-sm font-medium text-neutral-700">
          Contact name
        </label>
        <input id="contactName" name="contactName" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="companyName" className="text-sm font-medium text-neutral-700">
          Company <span className="font-normal text-neutral-500">(optional)</span>
        </label>
        <input id="companyName" name="companyName" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="email" className="text-sm font-medium text-neutral-700">
          Email <span className="font-normal text-neutral-500">(one of email/phone required)</span>
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

      <Button type="submit" loading={pending} loadingLabel="Capturing…">
        Capture lead
      </Button>
    </form>
  );
}
