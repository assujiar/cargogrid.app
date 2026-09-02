"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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

  // ISS-2026-242: one server-action error covers the whole submission, so every field points at
  // it rather than inventing a per-field attribution the action itself never returns.
  const describedBy = state.error ? "apply-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="fullName" label="Full name">
        <Input id="fullName" name="fullName" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="email" label="Email">
        <Input id="email" name="email" type="email" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="phone" label="Phone (optional)">
        <Input id="phone" name="phone" type="tel" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <Checkbox
        id="consentGiven"
        name="consentGiven"
        required
        label="I consent to my personal data being processed for the purpose of this job application, in line with the organization's privacy policy."
        aria-describedby={describedBy}
      />

      {state.error ? <ValidationMessage id="apply-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Submitting…">
        Submit application
      </Button>
    </form>
  );
}
