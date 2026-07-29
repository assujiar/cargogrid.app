"use client";

/** Settlement client forms (FIN-201, CG-S9-FIN-012). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceSettlementFormState } from "./actions.ts";

const INITIAL_STATE: FinanceSettlementFormState = { error: null };

type BoundAction = (prevState: FinanceSettlementFormState, formData: FormData) => Promise<FinanceSettlementFormState>;

export function PrepareFinanceSettlementForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Prepare settlement</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit. Enter a comma-separated list of AP open item IDs and a matching comma-separated list of amounts (same length, same order) --
        an exact allocation set decided once. Idempotent per idempotency key.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="vendorMasterId" className="text-sm font-medium text-text-primary">
            Vendor master ID
          </label>
          <input id="vendorMasterId" name="vendorMasterId" type="text" required className="w-80 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="apOpenItemIds" className="text-sm font-medium text-text-primary">
            AP open item IDs (comma-separated)
          </label>
          <input id="apOpenItemIds" name="apOpenItemIds" type="text" required className="w-80 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="amounts" className="text-sm font-medium text-text-primary">
            Amounts (comma-separated)
          </label>
          <input id="amounts" name="amounts" type="text" required placeholder="400, 500" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="currency" className="text-sm font-medium text-text-primary">
            Currency
          </label>
          <input id="currency" name="currency" type="text" required maxLength={3} placeholder="USD" className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="settlementDate" className="text-sm font-medium text-text-primary">
            Settlement date
          </label>
          <input id="settlementDate" name="settlementDate" type="date" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="feeAmount" className="text-sm font-medium text-text-primary">
            Fee amount (optional)
          </label>
          <input id="feeAmount" name="feeAmount" type="number" step="0.01" min="0" defaultValue={0} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="paymentReference" className="text-sm font-medium text-text-primary">
            Payment reference (optional)
          </label>
          <input id="paymentReference" name="paymentReference" type="text" maxLength={100} className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="bankAccountLabel" className="text-sm font-medium text-text-primary">
            Bank account label (optional)
          </label>
          <input id="bankAccountLabel" name="bankAccountLabel" type="text" maxLength={100} placeholder="Bank ***1234" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
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

      <Button type="submit" loading={pending} loadingLabel="Preparing…" className="w-fit">
        Prepare settlement
      </Button>
    </form>
  );
}

export function SubmitFinanceSettlementForApprovalForm({ action }: { action: BoundAction }) {
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

export function DiscardFinanceSettlementDraftForm({ action }: { action: BoundAction }) {
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

export function ApproveFinanceSettlementForm({ action }: { action: BoundAction }) {
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

export function ExecuteFinanceSettlementForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="executionReference" type="text" placeholder="Bank/payment reference (optional)" className="w-48 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Recording execution…">
        Record execution
      </Button>
    </form>
  );
}

export function PostFinanceSettlementForm({ action }: { action: BoundAction }) {
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

export function RequestFinanceSettlementReversalForm({ action }: { action: (prevState: FinanceSettlementFormState, formData: FormData) => Promise<FinanceSettlementFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="reason" type="text" required placeholder="Reason (required)" className="w-48 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reversing…">
        Request reversal
      </Button>
    </form>
  );
}
