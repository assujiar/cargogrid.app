"use client";

/** Chart of Accounts client forms (FIN-192, CG-S9-FIN-003). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { ChartOfAccountsFormState } from "./actions.ts";
import type { FinanceAccount } from "../../../../../server/contracts/chart-of-accounts/chart-of-accounts.ts";

const INITIAL_STATE: ChartOfAccountsFormState = { error: null };

type BoundAction = (prevState: ChartOfAccountsFormState, formData: FormData) => Promise<ChartOfAccountsFormState>;

export function CreateFinanceAccountForm({ action, parentCandidates }: { action: BoundAction; parentCandidates: readonly FinanceAccount[] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create an account (draft)</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Create to draft; FIN:Approve to activate.</p>

      <div className="flex flex-col gap-1">
        <label htmlFor="code" className="text-sm font-medium text-text-primary">
          Code
        </label>
        <input id="code" name="code" type="text" required maxLength={20} className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="name" className="text-sm font-medium text-text-primary">
          Name
        </label>
        <input id="name" name="name" type="text" required className="w-full max-w-md rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="accountType" className="text-sm font-medium text-text-primary">
          Account type
        </label>
        <select id="accountType" name="accountType" required defaultValue="" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="" disabled>
            Select a type…
          </option>
          <option value="asset">Asset (debit)</option>
          <option value="liability">Liability (credit)</option>
          <option value="equity">Equity (credit)</option>
          <option value="revenue">Revenue (credit)</option>
          <option value="expense">Expense (debit)</option>
        </select>
        <p className="text-xs text-text-secondary">Normal balance is derived automatically from the account type -- never independently configurable (canonical accounting identity).</p>
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="parentAccountId" className="text-sm font-medium text-text-primary">
          Parent account (optional)
        </label>
        <select id="parentAccountId" name="parentAccountId" defaultValue="" className="w-full max-w-md rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="">No parent -- a root account</option>
          {parentCandidates.map((account) => (
            <option key={account.id} value={account.id}>
              {account.code} -- {account.name}
            </option>
          ))}
        </select>
      </div>

      <div className="flex items-center gap-2">
        <input id="isControlAccount" name="isControlAccount" type="checkbox" className="h-4 w-4" />
        <label htmlFor="isControlAccount" className="text-sm text-text-primary">
          Control account (never directly postable)
        </label>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create account (draft)
      </Button>
    </form>
  );
}

export function ActivateFinanceAccountForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Activating…" variant="secondary">
        Activate
      </Button>
    </form>
  );
}

export function DeactivateFinanceAccountForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input type="text" name="reason" placeholder="Reason (required)" required className="w-40 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Deactivating…" variant="destructive">
        Deactivate
      </Button>
    </form>
  );
}
