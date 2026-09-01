"use client";

/** Double-Entry Journal client forms (FIN-203, CG-S9-FIN-014). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceJournalFormState } from "./actions.ts";

const INITIAL_STATE: FinanceJournalFormState = { error: null };

type BoundAction = (prevState: FinanceJournalFormState, formData: FormData) => Promise<FinanceJournalFormState>;

export function CreateFinanceJournalDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Prepare manual journal</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit. Enter matching comma-separated lists of account IDs, directions (debit/credit), and amounts (same length, same order,
        at least 2 lines) -- debit total must exactly equal credit total. Idempotent per idempotency key.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="w-96">
          <FormField id="accountIds" label="Account IDs (comma-separated)">
            <Input id="accountIds" name="accountIds" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="directions" label="Directions (comma-separated)">
            <Input id="directions" name="directions" type="text" required placeholder="debit, credit" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="amounts" label="Amounts (comma-separated)">
            <Input id="amounts" name="amounts" type="text" required placeholder="500, 500" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="journalDate" label="Journal date">
            <Input id="journalDate" name="journalDate" type="date" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-24">
          <FormField id="currency" label="Currency">
            <Input id="currency" name="currency" type="text" required maxLength={3} placeholder="USD" className="uppercase" invalid={Boolean(state.error)} />
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
        Prepare journal
      </Button>
    </form>
  );
}

export function SubmitFinanceJournalForApprovalForm({ action }: { action: BoundAction }) {
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

export function DiscardFinanceJournalDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="discard-journal-reason" className="sr-only">
        Reason
      </label>
      <Input id="discard-journal-reason" name="reason" type="text" placeholder="Reason (optional)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Voiding…">
        Discard
      </Button>
    </form>
  );
}

export function ApproveFinanceJournalForm({ action }: { action: BoundAction }) {
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

export function PostFinanceJournalForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Posting…">
        Post
      </Button>
    </form>
  );
}
