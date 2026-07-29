"use client";

/** Cash and Bank Baseline client forms (FIN-211, CG-S9-FIN-022). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
        <div className="flex flex-col gap-1">
          <label htmlFor="cb-accountName" className="text-sm font-medium text-text-primary">
            Account name
          </label>
          <input id="cb-accountName" name="accountName" type="text" required className="w-56 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="cb-bankName" className="text-sm font-medium text-text-primary">
            Bank name
          </label>
          <input id="cb-bankName" name="bankName" type="text" required className="w-56 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="cb-accountNumberLast4" className="text-sm font-medium text-text-primary">
            Last 4 digits
          </label>
          <input id="cb-accountNumberLast4" name="accountNumberLast4" type="text" required maxLength={4} className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="cb-currency" className="text-sm font-medium text-text-primary">
            Currency
          </label>
          <input id="cb-currency" name="currency" type="text" required maxLength={3} placeholder="USD" className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="cb-glAccountId" className="text-sm font-medium text-text-primary">
            GL account ID
          </label>
          <input id="cb-glAccountId" name="glAccountId" type="text" required className="w-72 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

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
        <div className="flex flex-col gap-1">
          <label htmlFor="cb-bankAccountId" className="text-sm font-medium text-text-primary">
            Bank account ID
          </label>
          <input id="cb-bankAccountId" name="bankAccountId" type="text" required className="w-72 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="cb-sourceReference" className="text-sm font-medium text-text-primary">
            Source reference
          </label>
          <input id="cb-sourceReference" name="sourceReference" type="text" required className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor="cb-linesJson" className="text-sm font-medium text-text-primary">
            Lines (JSON array)
          </label>
          <textarea
            id="cb-linesJson"
            name="linesJson"
            required
            rows={3}
            placeholder='[{"transactionDate":"2026-07-01","direction":"credit","amount":500,"reference":"REF-1"}]'
            className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs"
          />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

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
      <select name="matchedSourceType" required defaultValue="manual" className="w-28 rounded-md border border-neutral-300 px-2 py-1 text-xs">
        <option value="receipt">receipt</option>
        <option value="settlement">settlement</option>
        <option value="manual">manual</option>
      </select>
      <input name="matchedSourceId" type="text" placeholder="Source ID (optional)" className="w-40 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      <input name="reason" type="text" required placeholder="Reason (required)" className="w-40 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Unmatching…">
        Unmatch
      </Button>
    </form>
  );
}
