"use client";

/** Double-Entry Journal client forms (FIN-203, CG-S9-FIN-014). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
        <div className="flex flex-col gap-1">
          <label htmlFor="accountIds" className="text-sm font-medium text-text-primary">
            Account IDs (comma-separated)
          </label>
          <input id="accountIds" name="accountIds" type="text" required className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="directions" className="text-sm font-medium text-text-primary">
            Directions (comma-separated)
          </label>
          <input id="directions" name="directions" type="text" required placeholder="debit, credit" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="amounts" className="text-sm font-medium text-text-primary">
            Amounts (comma-separated)
          </label>
          <input id="amounts" name="amounts" type="text" required placeholder="500, 500" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="journalDate" className="text-sm font-medium text-text-primary">
            Journal date
          </label>
          <input id="journalDate" name="journalDate" type="date" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="currency" className="text-sm font-medium text-text-primary">
            Currency
          </label>
          <input id="currency" name="currency" type="text" required maxLength={3} placeholder="USD" className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
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
        Prepare journal
      </Button>
    </form>
  );
}

export function SubmitFinanceJournalForApprovalForm({ action }: { action: BoundAction }) {
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

export function DiscardFinanceJournalDraftForm({ action }: { action: BoundAction }) {
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

export function ApproveFinanceJournalForm({ action }: { action: BoundAction }) {
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

export function PostFinanceJournalForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Posting…">
        Post
      </Button>
    </form>
  );
}
