"use client";

/** Settlement client forms (FIN-201, CG-S9-FIN-012). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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
        <div className="w-80">
          <FormField id="vendorMasterId" label="Vendor master ID">
            <Input id="vendorMasterId" name="vendorMasterId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-80">
          <FormField id="apOpenItemIds" label="AP open item IDs (comma-separated)">
            <Input id="apOpenItemIds" name="apOpenItemIds" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="amounts" label="Amounts (comma-separated)">
            <Input id="amounts" name="amounts" type="text" required placeholder="400, 500" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-24">
          <FormField id="currency" label="Currency">
            <Input id="currency" name="currency" type="text" required maxLength={3} placeholder="USD" className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="settlementDate" label="Settlement date">
            <Input id="settlementDate" name="settlementDate" type="date" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-32">
          <FormField id="feeAmount" label="Fee amount (optional)">
            <Input id="feeAmount" name="feeAmount" type="number" step="0.01" min="0" defaultValue={0} invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="paymentReference" label="Payment reference (optional)">
            <Input id="paymentReference" name="paymentReference" type="text" maxLength={100} invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="bankAccountLabel" label="Bank account label (optional)">
            <Input id="bankAccountLabel" name="bankAccountLabel" type="text" maxLength={100} placeholder="Bank ***1234" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="idempotencyKey" label="Idempotency key">
            <Input id="idempotencyKey" name="idempotencyKey" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      <label htmlFor="discard-settlement-reason" className="sr-only">
        Reason
      </label>
      <Input id="discard-settlement-reason" name="reason" type="text" placeholder="Reason (optional)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      <label htmlFor="execution-reference" className="sr-only">
        Bank/payment reference
      </label>
      <Input id="execution-reference" name="executionReference" type="text" placeholder="Bank/payment reference (optional)" className="w-48 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      <label htmlFor="settlement-reversal-reason" className="sr-only">
        Reason
      </label>
      <Input id="settlement-reversal-reason" name="reason" type="text" required placeholder="Reason (required)" className="w-48 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reversing…">
        Request reversal
      </Button>
    </form>
  );
}
