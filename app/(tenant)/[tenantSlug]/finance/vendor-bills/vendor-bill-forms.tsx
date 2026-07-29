"use client";

/** Vendor Bill client forms (FIN-200, CG-S9-FIN-011). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
        <div className="flex flex-col gap-1">
          <label htmlFor="actualCostId" className="text-sm font-medium text-text-primary">
            Actual cost ID
          </label>
          <input id="actualCostId" name="actualCostId" type="text" required className="w-80 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="vendorMasterId" className="text-sm font-medium text-text-primary">
            Vendor master ID
          </label>
          <input id="vendorMasterId" name="vendorMasterId" type="text" required className="w-80 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="vendorReference" className="text-sm font-medium text-text-primary">
            Vendor reference (optional)
          </label>
          <input id="vendorReference" name="vendorReference" type="text" maxLength={100} className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="billDate" className="text-sm font-medium text-text-primary">
            Bill date
          </label>
          <input id="billDate" name="billDate" type="date" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="paymentTermDays" className="text-sm font-medium text-text-primary">
            Payment term (days)
          </label>
          <input id="paymentTermDays" name="paymentTermDays" type="number" min="0" defaultValue={30} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="vendorStatedAmount" className="text-sm font-medium text-text-primary">
            Vendor-stated amount (optional)
          </label>
          <input id="vendorStatedAmount" name="vendorStatedAmount" type="number" step="0.01" min="0" className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="taxCode" className="text-sm font-medium text-text-primary">
            Tax code (optional)
          </label>
          <input id="taxCode" name="taxCode" type="text" placeholder="PPN" maxLength={20} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

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
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      <input name="reason" type="text" placeholder="Reason (optional)" className="w-40 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Posting…">
        Post (post to AP)
      </Button>
    </form>
  );
}
