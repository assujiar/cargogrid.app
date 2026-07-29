"use client";

/** Receipt and Payment Allocation client forms (FIN-198, CG-S9-FIN-009). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
        <div className="flex flex-col gap-1">
          <label htmlFor="customerAccountId" className="text-sm font-medium text-text-primary">
            Customer account ID
          </label>
          <input id="customerAccountId" name="customerAccountId" type="text" required className="w-72 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="receiptReference" className="text-sm font-medium text-text-primary">
            Bank reference (optional)
          </label>
          <input id="receiptReference" name="receiptReference" type="text" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="receiptDate" className="text-sm font-medium text-text-primary">
            Receipt date
          </label>
          <input id="receiptDate" name="receiptDate" type="date" required className="w-44 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="payerName" className="text-sm font-medium text-text-primary">
            Payer name
          </label>
          <input id="payerName" name="payerName" type="text" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="bankAccountLabel" className="text-sm font-medium text-text-primary">
            Bank account label
          </label>
          <input id="bankAccountLabel" name="bankAccountLabel" type="text" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="currency" className="text-sm font-medium text-text-primary">
            Currency
          </label>
          <input id="currency" name="currency" type="text" maxLength={3} placeholder="IDR" required className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="amount" className="text-sm font-medium text-text-primary">
            Amount
          </label>
          <input id="amount" name="amount" type="number" step="0.01" min="0" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="idempotencyKey" className="text-sm font-medium text-text-primary">
            Idempotency key
          </label>
          <input id="idempotencyKey" name="idempotencyKey" type="text" required className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

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
      <input name="idempotencyKey" type="text" placeholder="Allocation idempotency key" required className="w-64 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      <textarea
        name="allocations"
        rows={3}
        placeholder='[{"arOpenItemId": "…", "amount": 100000}]'
        required
        className="w-96 rounded-md border border-neutral-300 px-2 py-1 font-mono text-xs"
      />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      <input name="reason" type="text" placeholder="Reversal reason (required)" required className="w-56 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reversing…">
        Reverse (FIN:Approve)
      </Button>
    </form>
  );
}
