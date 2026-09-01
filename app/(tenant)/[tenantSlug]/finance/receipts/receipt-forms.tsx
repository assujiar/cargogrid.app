"use client";

/** Receipt and Payment Allocation client forms (FIN-198, CG-S9-FIN-009). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceReceiptFormState } from "./actions.ts";

const INITIAL_STATE: FinanceReceiptFormState = { error: null };

type BoundAction = (prevState: FinanceReceiptFormState, formData: FormData) => Promise<FinanceReceiptFormState>;

export function CaptureFinanceReceiptForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Capture a receipt</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Edit. Bank/payment fields are sensitive -- restrict this workspace to authorized Accounting staff.</p>

      <div className="flex flex-wrap gap-3">
        <div className="w-72">
          <FormField id="customerAccountId" label="Customer account ID">
            <Input id="customerAccountId" name="customerAccountId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="receiptReference" label="Bank reference (optional)">
            <Input id="receiptReference" name="receiptReference" type="text" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-44">
          <FormField id="receiptDate" label="Receipt date">
            <Input id="receiptDate" name="receiptDate" type="date" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      <div className="flex flex-wrap gap-3">
        <div className="w-48">
          <FormField id="payerName" label="Payer name">
            <Input id="payerName" name="payerName" type="text" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="bankAccountLabel" label="Bank account label">
            <Input id="bankAccountLabel" name="bankAccountLabel" type="text" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-24">
          <FormField id="currency" label="Currency">
            <Input id="currency" name="currency" type="text" maxLength={3} placeholder="IDR" required className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="amount" label="Amount">
            <Input id="amount" name="amount" type="number" step="0.01" min="0" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="idempotencyKey" label="Idempotency key">
            <Input id="idempotencyKey" name="idempotencyKey" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Capturing…" className="w-fit">
        Capture receipt
      </Button>
    </form>
  );
}

export function AllocateFinanceReceiptForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <label htmlFor="allocate-idempotency-key" className="sr-only">
        Allocation idempotency key
      </label>
      <Input id="allocate-idempotency-key" name="idempotencyKey" type="text" placeholder="Allocation idempotency key" required className="w-64 text-xs" invalid={Boolean(state.error)} />
      <label htmlFor="allocate-allocations" className="sr-only">
        Allocations
      </label>
      <Textarea
        id="allocate-allocations"
        name="allocations"
        rows={3}
        placeholder='[{"arOpenItemId": "…", "amount": 100000}]'
        required
        className="w-96 font-mono text-xs"
        invalid={Boolean(state.error)}
      />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Allocating…" className="w-fit">
        Allocate
      </Button>
    </form>
  );
}

export function RequestFinanceReceiptDeallocationForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="deallocation-reason" className="sr-only">
        Reversal reason
      </label>
      <Input id="deallocation-reason" name="reason" type="text" placeholder="Reversal reason (required)" required className="w-56 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reversing…">
        Reverse (FIN:Approve)
      </Button>
    </form>
  );
}
