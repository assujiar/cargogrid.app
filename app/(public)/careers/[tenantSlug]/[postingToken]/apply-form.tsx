"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { submitPublicJobApplicationAction, type PublicApplicationFormState } from "./actions.ts";

const INITIAL_STATE: PublicApplicationFormState = { error: null, result: null };

/** HRT-276: the one public job-application intake form. Consent is a required checkbox, never pre-checked. */
export function ApplyForm({ postingToken }: { postingToken: string }) {
  const boundAction = submitPublicJobApplicationAction.bind(null, postingToken);
  const [state, formAction, pending] = useActionState(boundAction, INITIAL_STATE);

  if (state.result?.submitStatus === "ok") {
    return (
      <div role="status" className="rounded-md border border-success/30 bg-success/10 p-4 text-sm text-neutral-900">
        Thank you for applying -- we&apos;ve received your application and will be in touch.
      </div>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <div className="flex flex-col gap-1">
        <label htmlFor="fullName" className="text-sm font-medium text-neutral-700">
          Full name
        </label>
        <input id="fullName" name="fullName" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="email" className="text-sm font-medium text-neutral-700">
          Email
        </label>
        <input id="email" name="email" type="email" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="phone" className="text-sm font-medium text-neutral-700">
          Phone (optional)
        </label>
        <input id="phone" name="phone" type="tel" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <label className="flex items-start gap-2 text-sm text-neutral-700">
        <input name="consentGiven" type="checkbox" required className="mt-0.5" />
        <span>I consent to my personal data being processed for the purpose of this job application, in line with the organization&apos;s privacy policy.</span>
      </label>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Submitting…">
        Submit application
      </Button>
    </form>
  );
}
