"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { RateFormState } from "./actions.ts";

const INITIAL_STATE: RateFormState = { error: null };

/** Client Component wrapper (COM-149) -- same `useActionState`/bound-action split every prior Commercial create-form already uses. */
export function CreateRateVersionForm({ action }: { action: (prevState: RateFormState, formData: FormData) => Promise<RateFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a rate version</h2>
      <p className="text-xs text-neutral-500">Requires tenant_admin (or Supreme Admin) authority -- a Commercial rep will see a denial here, which is expected.</p>

      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="vendorCode" className="text-sm font-medium text-neutral-700">Vendor code</label>
          <input id="vendorCode" name="vendorCode" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="vendorName" className="text-sm font-medium text-neutral-700">Vendor name</label>
          <input id="vendorName" name="vendorName" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="serviceType" className="text-sm font-medium text-neutral-700">Service type</label>
          <input id="serviceType" name="serviceType" type="text" placeholder="ocean_freight" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="originLane" className="text-sm font-medium text-neutral-700">Origin</label>
          <input id="originLane" name="originLane" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="destinationLane" className="text-sm font-medium text-neutral-700">Destination</label>
          <input id="destinationLane" name="destinationLane" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="currency" className="text-sm font-medium text-neutral-700">Currency</label>
          <input id="currency" name="currency" type="text" placeholder="IDR" maxLength={3} required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="baseAmount" className="text-sm font-medium text-neutral-700">Base amount</label>
          <input id="baseAmount" name="baseAmount" type="number" min={0} required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
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
