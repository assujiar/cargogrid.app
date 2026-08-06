"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
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
        <div className="flex flex-col gap-1">
          <label htmlFor="vendorCode" className="text-sm font-medium text-neutral-700">Vendor code</label>
          <Input id="vendorCode" name="vendorCode" type="text" required />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="vendorName" className="text-sm font-medium text-neutral-700">Vendor name</label>
          <Input id="vendorName" name="vendorName" type="text" required />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="vendorMasterId" className="text-sm font-medium text-neutral-700">Linked vendor (master record id, optional)</label>
          <Input id="vendorMasterId" name="vendorMasterId" type="text" placeholder="uuid of a registered vendor" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="serviceType" className="text-sm font-medium text-neutral-700">Service type</label>
          <Input id="serviceType" name="serviceType" type="text" placeholder="ocean_freight" required />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="originLane" className="text-sm font-medium text-neutral-700">Origin</label>
          <Input id="originLane" name="originLane" type="text" required />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="destinationLane" className="text-sm font-medium text-neutral-700">Destination</label>
          <Input id="destinationLane" name="destinationLane" type="text" required />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="currency" className="text-sm font-medium text-neutral-700">Currency</label>
          <Input id="currency" name="currency" type="text" placeholder="IDR" maxLength={3} required />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="baseAmount" className="text-sm font-medium text-neutral-700">Base amount</label>
          <Input id="baseAmount" name="baseAmount" type="number" min={0} required />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="leadTimeDays" className="text-sm font-medium text-neutral-700">Lead time (days, optional)</label>
          <Input id="leadTimeDays" name="leadTimeDays" type="number" min={0} />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="capacityTerms" className="text-sm font-medium text-neutral-700">Capacity terms (optional)</label>
          <Input id="capacityTerms" name="capacityTerms" type="text" placeholder="e.g. 4 x 20ft/week" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create rate version
      </Button>
    </form>
  );
}
