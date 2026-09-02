"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { SuccessState } from "../../../../../components/ui/success-state.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { submitVendorSelfRegistrationAction, type VendorSelfRegistrationFormState } from "./actions.ts";

const INITIAL_STATE: VendorSelfRegistrationFormState = { error: null, result: null };

/** PRC-251: the public, un-tokened self-registration form -- writes only a staged, submitted-status vendor profile under the already-resolved tenantId, never exposes any existing tenant/vendor data. */
export function VendorSelfRegistrationForm({ tenantId }: { tenantId: string }) {
  const boundAction = submitVendorSelfRegistrationAction.bind(null, tenantId);
  const [state, formAction, pending] = useActionState(boundAction, INITIAL_STATE);
  // Stable for the lifetime of this mounted form -- protects a network retry or a
  // double-click on submit from creating two staged registrations (the RPC's own
  // idempotency-key target-mismatch guard still rejects a genuinely different
  // resubmission reusing the same key, per app.submit_vendor_profile_self_registration).
  const [idempotencyKey] = useState(() => crypto.randomUUID());

  // ISS-2026-246: same whole-section confirmation as the tokened intake form above, and the same
  // reason -- `SuccessState` is this exact shape, and only `submitStatus === "ok"` reaches it.
  if (state.result?.submitStatus === "ok") {
    return <SuccessState title="Thank you -- your vendor registration has been submitted" description="It is now awaiting review." />;
  }

  // ISS-2026-242: one server-action error covers the whole submission, so every field is wired to
  // it rather than fabricating a per-field attribution the action does not return.
  const describedBy = state.error ? "vendor-self-registration-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />

      <FormField id="legalName" label="Legal company name">
        <Input id="legalName" name="legalName" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="tradeName" label="Trade name (optional)">
        <Input id="tradeName" name="tradeName" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="legalEntityType" label="Legal entity type (e.g. PT, CV, Perorangan)">
        <Input id="legalEntityType" name="legalEntityType" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="businessRegistrationNumber" label="Business registration number (optional)">
        <Input id="businessRegistrationNumber" name="businessRegistrationNumber" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="vendorCategory" label="Service category (e.g. trucking, warehousing)">
        <Input id="vendorCategory" name="vendorCategory" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="paymentTermDays" label="Requested payment term (days, optional)">
        <NumberInput id="paymentTermDays" name="paymentTermDays" min="0" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="contactName" label="Primary contact name">
        <Input id="contactName" name="contactName" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="contactEmail" label="Primary contact email">
        <Input id="contactEmail" name="contactEmail" type="email" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <FormField id="contactPhone" label="Primary contact phone">
        <Input id="contactPhone" name="contactPhone" type="tel" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      {state.error ? <ValidationMessage id="vendor-self-registration-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Submitting…">
        Submit registration
      </Button>
    </form>
  );
}
