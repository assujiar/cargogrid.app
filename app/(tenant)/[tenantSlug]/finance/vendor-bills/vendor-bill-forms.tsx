"use client";

/** Vendor Bill client forms (FIN-200, CG-S9-FIN-011). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceVendorBillFormState } from "./actions.ts";

const INITIAL_STATE: FinanceVendorBillFormState = { error: null };

type BoundAction = (prevState: FinanceVendorBillFormState, formData: FormData) => Promise<FinanceVendorBillFormState>;

export function PrepareFinanceVendorBillFromActualCostForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Prepare vendor bill from actual cost</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit. Idempotent per (actual cost, vendor) pair -- sums only the requested vendor&apos;s own approved actual-cost components. An
        optional vendor-stated amount is compared against the computed subtotal (1.00 tolerance); a materially different amount discloses
        <code>requires_approval</code> to the approver but does not itself block approval.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="w-80">
          <FormField id="actualCostId" label="Actual cost ID">
            <Input id="actualCostId" name="actualCostId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-80">
          <FormField id="vendorMasterId" label="Vendor master ID">
            <Input id="vendorMasterId" name="vendorMasterId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="vendorReference" label="Vendor reference (optional)">
            <Input id="vendorReference" name="vendorReference" type="text" maxLength={100} invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="billDate" label="Bill date">
            <Input id="billDate" name="billDate" type="date" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-32">
          <FormField id="paymentTermDays" label="Payment term (days)">
            <Input id="paymentTermDays" name="paymentTermDays" type="number" min="0" defaultValue={30} invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="vendorStatedAmount" label="Vendor-stated amount (optional)">
            <Input id="vendorStatedAmount" name="vendorStatedAmount" type="number" step="0.01" min="0" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-32">
          <FormField id="taxCode" label="Tax code (optional)">
            <Input id="taxCode" name="taxCode" type="text" placeholder="PPN" maxLength={20} className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Preparing…" className="w-fit">
        Prepare vendor bill
      </Button>
    </form>
  );
}

export function SubmitFinanceVendorBillForApprovalForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
        Submit
      </Button>
    </form>
  );
}

export function DiscardFinanceVendorBillDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="discard-vendor-bill-reason" className="sr-only">
        Reason
      </label>
      <Input id="discard-vendor-bill-reason" name="reason" type="text" placeholder="Reason (optional)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Voiding…">
        Discard
      </Button>
    </form>
  );
}

export function ApproveFinanceVendorBillForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Approving…">
        Approve
      </Button>
    </form>
  );
}

export function PostFinanceVendorBillForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Posting…">
        Post (post to AP)
      </Button>
    </form>
  );
}
