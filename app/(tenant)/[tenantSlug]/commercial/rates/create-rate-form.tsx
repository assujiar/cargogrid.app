"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { RateFormState } from "./actions.ts";
import { Input } from "../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";

const INITIAL_STATE: RateFormState = { error: null };

/** Client Component wrapper (COM-149) -- same `useActionState`/bound-action split every prior Commercial create-form already uses. */
export function CreateRateVersionForm({ action }: { action: (prevState: RateFormState, formData: FormData) => Promise<RateFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  const describedBy = state.error ? "create-rate-error" : undefined;
  const invalid = Boolean(state.error);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a rate version</h2>
      <p className="text-xs text-neutral-500">Requires tenant_admin (or Supreme Admin) authority -- a Commercial rep will see a denial here, which is expected.</p>

      <div className="grid grid-cols-2 gap-3">
        <FormField id="vendorCode" label="Vendor code">
          <Input id="vendorCode" name="vendorCode" type="text" required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="vendorName" label="Vendor name">
          <Input id="vendorName" name="vendorName" type="text" required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="serviceType" label="Service type">
          <Input id="serviceType" name="serviceType" type="text" placeholder="ocean_freight" required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="originLane" label="Origin">
          <Input id="originLane" name="originLane" type="text" required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="destinationLane" label="Destination">
          <Input id="destinationLane" name="destinationLane" type="text" required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="currency" label="Currency">
          <Input id="currency" name="currency" type="text" placeholder="IDR" maxLength={3} required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="baseAmount" label="Base amount">
          <Input type="number" inputMode="decimal" id="baseAmount" name="baseAmount" min={0} required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
      </div>

      {state.error ? <ValidationMessage id="create-rate-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create rate version
      </Button>
    </form>
  );
}
