"use client";

/** Chart of Accounts client forms (FIN-192, CG-S9-FIN-003). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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

      <FormField id="code" label="Code">
        <Input id="code" name="code" type="text" required maxLength={20} className="w-48" invalid={Boolean(state.error)} />
      </FormField>

      <FormField id="name" label="Name">
        <Input id="name" name="name" type="text" required className="w-full max-w-md" invalid={Boolean(state.error)} />
      </FormField>

      <FormField id="accountType" label="Account type" helpText="Normal balance is derived automatically from the account type -- never independently configurable (canonical accounting identity).">
        <Select id="accountType" name="accountType" required defaultValue="" className="w-48" invalid={Boolean(state.error)}>
          <option value="" disabled>
            Select a type…
          </option>
          <option value="asset">Asset (debit)</option>
          <option value="liability">Liability (credit)</option>
          <option value="equity">Equity (credit)</option>
          <option value="revenue">Revenue (credit)</option>
          <option value="expense">Expense (debit)</option>
        </Select>
      </FormField>

      <FormField id="parentAccountId" label="Parent account (optional)">
        <Select id="parentAccountId" name="parentAccountId" defaultValue="" className="w-full max-w-md">
          <option value="">No parent -- a root account</option>
          {parentCandidates.map((account) => (
            <option key={account.id} value={account.id}>
              {account.code} -- {account.name}
            </option>
          ))}
        </Select>
      </FormField>

      <Checkbox id="isControlAccount" name="isControlAccount" label="Control account (never directly postable)" />

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      <label htmlFor="deactivate-account-reason" className="sr-only">
        Reason
      </label>
      <Input id="deactivate-account-reason" type="text" name="reason" placeholder="Reason (required)" required className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Deactivating…" variant="destructive">
        Deactivate
      </Button>
    </form>
  );
}
