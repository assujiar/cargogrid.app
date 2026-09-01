"use client";

/** Cash and Bank Baseline client forms (FIN-211, CG-S9-FIN-022). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceCashBankFormState } from "./actions.ts";

const INITIAL_STATE: FinanceCashBankFormState = { error: null };

type BoundAction = (prevState: FinanceCashBankFormState, formData: FormData) => Promise<FinanceCashBankFormState>;

export function CreateFinanceBankAccountForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Add a bank/cash account</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Approve. Only the last 1-4 characters of the account number are ever stored.</p>

      <div className="flex flex-wrap gap-3">
        <div className="w-56">
          <FormField id="cb-accountName" label="Account name">
            <Input id="cb-accountName" name="accountName" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
        <div className="w-56">
          <FormField id="cb-bankName" label="Bank name">
            <Input id="cb-bankName" name="bankName" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
        <div className="w-24">
          <FormField id="cb-accountNumberLast4" label="Last 4 digits">
            <Input id="cb-accountNumberLast4" name="accountNumberLast4" type="text" required maxLength={4} invalid={Boolean(state.error)} />
          </FormField>
        </div>
        <div className="w-24">
          <FormField id="cb-currency" label="Currency">
            <Input id="cb-currency" name="currency" type="text" required maxLength={3} placeholder="USD" className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>
        <div className="w-72">
          <FormField id="cb-glAccountId" label="GL account ID">
            <Input id="cb-glAccountId" name="glAccountId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add account
      </Button>
    </form>
  );
}

export function ImportFinanceBankStatementForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Import a statement</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit. A staged, idempotent import of an already-parsed batch of lines -- no live bank-provider connection. Every line is
        deduplicated by the database itself; a re-imported line is silently skipped, never double-counted.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="w-72">
          <FormField id="cb-bankAccountId" label="Bank account ID">
            <Input id="cb-bankAccountId" name="bankAccountId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
        <div className="w-48">
          <FormField id="cb-sourceReference" label="Source reference">
            <Input id="cb-sourceReference" name="sourceReference" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
        <div className="flex-1">
          <FormField id="cb-linesJson" label="Lines (JSON array)">
            <Textarea
              id="cb-linesJson"
              name="linesJson"
              required
              rows={3}
              placeholder='[{"transactionDate":"2026-07-01","direction":"credit","amount":500,"reference":"REF-1"}]'
              className="font-mono text-xs"
              invalid={Boolean(state.error)}
            />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Importing…" className="w-fit">
        Import statement
      </Button>
    </form>
  );
}

export function MatchFinanceBankTransactionForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="match-source-type" className="sr-only">
        Matched source type
      </label>
      <Select id="match-source-type" name="matchedSourceType" required defaultValue="manual" className="w-28 text-xs" invalid={Boolean(state.error)}>
        <option value="receipt">receipt</option>
        <option value="settlement">settlement</option>
        <option value="manual">manual</option>
      </Select>
      <label htmlFor="match-source-id" className="sr-only">
        Source ID
      </label>
      <Input id="match-source-id" name="matchedSourceId" type="text" placeholder="Source ID (optional)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Matching…">
        Match
      </Button>
    </form>
  );
}

export function UnmatchFinanceBankTransactionForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="unmatch-reason" className="sr-only">
        Reason
      </label>
      <Input id="unmatch-reason" name="reason" type="text" required placeholder="Reason (required)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Unmatching…">
        Unmatch
      </Button>
    </form>
  );
}
