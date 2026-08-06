"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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

  if (state.result?.submitStatus === "ok") {
    return (
      <div role="status" className="rounded-md border border-success/30 bg-success/10 p-4 text-sm text-neutral-900">
        Thank you -- your vendor registration has been submitted and is now awaiting review.
      </div>
    );
  }

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <input type="hidden" name="idempotencyKey" value={idempotencyKey} />

      <div className="flex flex-col gap-1">
        <label htmlFor="legalName" className="text-sm font-medium text-neutral-700">
          Legal company name
        </label>
        <input id="legalName" name="legalName" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="tradeName" className="text-sm font-medium text-neutral-700">
          Trade name (optional)
        </label>
        <input id="tradeName" name="tradeName" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="legalEntityType" className="text-sm font-medium text-neutral-700">
          Legal entity type (e.g. PT, CV, Perorangan)
        </label>
        <input id="legalEntityType" name="legalEntityType" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="businessRegistrationNumber" className="text-sm font-medium text-neutral-700">
          Business registration number (optional)
        </label>
        <input id="businessRegistrationNumber" name="businessRegistrationNumber" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="vendorCategory" className="text-sm font-medium text-neutral-700">
          Service category (e.g. trucking, warehousing)
        </label>
        <input id="vendorCategory" name="vendorCategory" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="paymentTermDays" className="text-sm font-medium text-neutral-700">
          Requested payment term (days, optional)
        </label>
        <input id="paymentTermDays" name="paymentTermDays" type="number" min="0" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="contactName" className="text-sm font-medium text-neutral-700">
          Primary contact name
        </label>
        <input id="contactName" name="contactName" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="contactEmail" className="text-sm font-medium text-neutral-700">
          Primary contact email
        </label>
        <input id="contactEmail" name="contactEmail" type="email" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="contactPhone" className="text-sm font-medium text-neutral-700">
          Primary contact phone
        </label>
        <input id="contactPhone" name="contactPhone" type="tel" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Submitting…">
        Submit registration
      </Button>
    </form>
  );
}
