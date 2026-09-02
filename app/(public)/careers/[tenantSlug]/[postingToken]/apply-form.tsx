"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { SuccessState } from "../../../../../components/ui/success-state.tsx";
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

  // ISS-2026-246: this branch replaces the whole form with a standalone confirmation -- the
  // whole-section shape `SuccessState` owns, down to the `role="status"` and the
  // `border-success/30 bg-success/10` tokens this markup was already hand-writing. Nothing here
  // can report a non-success outcome -- only `submitStatus === "ok"` reaches it, and every other
  // result stays on the form with its own `ValidationMessage` -- so the success tone is not
  // overstating anything, which is what ruled `SuccessState` out for the credit-check readout
  // that can settle `blocked_*`.
  if (state.result?.submitStatus === "ok") {
    return <SuccessState title="Thank you for applying" description="We've received your application and will be in touch." />;
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
