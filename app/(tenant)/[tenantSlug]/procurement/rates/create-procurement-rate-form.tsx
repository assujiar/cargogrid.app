"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { ProcurementRateActionState } from "./actions.ts";

const INITIAL_STATE: ProcurementRateActionState = { error: null };

/** Client Component wrapper (PRC-255) -- mirrors app/(tenant)/[tenantSlug]/commercial/rates/create-rate-form.tsx's own shape, with the three new ADR-0020 fields (vendor link, lead time, capacity terms) added. */
export function CreateProcurementRateForm({ action }: { action: (prevState: ProcurementRateActionState, formData: FormData) => Promise<ProcurementRateActionState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a vendor rate</h2>
      <p className="text-xs text-neutral-500">Requires tenant_admin (or Supreme Admin) authority, unchanged from the Commercial rate engine (ADR-0020). Optionally link this rate to a registered vendor for eligibility/vendor-active checks at approval.</p>

      <div className="grid grid-cols-2 gap-3">
        <FormField id="vendorCode" label="Vendor code">
          <Input id="vendorCode" name="vendorCode" type="text" required invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="vendorName" label="Vendor name">
          <Input id="vendorName" name="vendorName" type="text" required invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="vendorMasterId" label="Linked vendor (master record id, optional)">
          <Input id="vendorMasterId" name="vendorMasterId" type="text" placeholder="uuid of a registered vendor" invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="serviceType" label="Service type">
          <Input id="serviceType" name="serviceType" type="text" placeholder="ocean_freight" required invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="originLane" label="Origin">
          <Input id="originLane" name="originLane" type="text" required invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="destinationLane" label="Destination">
          <Input id="destinationLane" name="destinationLane" type="text" required invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="currency" label="Currency">
          <Input id="currency" name="currency" type="text" placeholder="IDR" maxLength={3} required invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="baseAmount" label="Base amount">
          <Input id="baseAmount" name="baseAmount" type="number" min={0} required invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="leadTimeDays" label="Lead time (days, optional)">
          <Input id="leadTimeDays" name="leadTimeDays" type="number" min={0} invalid={Boolean(state.error)} />
        </FormField>
        <FormField id="capacityTerms" label="Capacity terms (optional)">
          <Input id="capacityTerms" name="capacityTerms" type="text" placeholder="e.g. 4 x 20ft/week" invalid={Boolean(state.error)} />
        </FormField>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create rate version
      </Button>
    </form>
  );
}
