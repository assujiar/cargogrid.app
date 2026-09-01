"use client";

/** Customer Invoice client forms (FIN-197, CG-S9-FIN-008). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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
        <div className="w-96">
          <FormField id="billingReadinessHandoffId" label="BillingReadinessHandoff ID">
            <Input id="billingReadinessHandoffId" name="billingReadinessHandoffId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-32">
          <FormField id="paymentTermDays" label="Payment term (days)">
            <Input id="paymentTermDays" name="paymentTermDays" type="number" min="0" defaultValue={30} invalid={Boolean(state.error)} />
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
        Prepare invoice
      </Button>
    </form>
  );
}

export function SubmitFinanceInvoiceForApprovalForm({ action }: { action: BoundAction }) {
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

export function DiscardFinanceInvoiceDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="discard-invoice-reason" className="sr-only">
        Reason
      </label>
      <Input id="discard-invoice-reason" name="reason" type="text" placeholder="Reason (optional)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      <label htmlFor="issue-invoice-date" className="sr-only">
        Issue date
      </label>
      <Input id="issue-invoice-date" name="issueDate" type="date" required className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Issuing…">
        Issue (post to AR)
      </Button>
    </form>
  );
}
