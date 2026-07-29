"use client";

/** Customer Invoice client forms (FIN-197, CG-S9-FIN-008). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceInvoiceFormState } from "./actions.ts";

const INITIAL_STATE: FinanceInvoiceFormState = { error: null };

type BoundAction = (prevState: FinanceInvoiceFormState, formData: FormData) => Promise<FinanceInvoiceFormState>;

export function PrepareFinanceInvoiceFromReadinessForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Prepare invoice from readiness</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Edit. Idempotent per BillingReadinessHandoff -- inherits the exact governed revenue snapshot from Operations, never re-entered.</p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="billingReadinessHandoffId" className="text-sm font-medium text-text-primary">
            BillingReadinessHandoff ID
          </label>
          <input id="billingReadinessHandoffId" name="billingReadinessHandoffId" type="text" required className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="paymentTermDays" className="text-sm font-medium text-text-primary">
            Payment term (days)
          </label>
          <input id="paymentTermDays" name="paymentTermDays" type="number" min="0" defaultValue={30} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
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
        Prepare invoice
      </Button>
    </form>
  );
}

export function SubmitFinanceInvoiceForApprovalForm({ action }: { action: BoundAction }) {
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

export function DiscardFinanceInvoiceDraftForm({ action }: { action: BoundAction }) {
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

export function ApproveFinanceInvoiceForm({ action }: { action: BoundAction }) {
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

export function IssueFinanceInvoiceForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="issueDate" type="date" required className="w-40 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Issuing…">
        Issue (post to AR)
      </Button>
    </form>
  );
}
