"use client";

/** Reversal and Adjustment client forms (FIN-206, CG-S9-FIN-017). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceCorrectionFormState } from "./actions.ts";

const INITIAL_STATE: FinanceCorrectionFormState = { error: null };

type BoundAction = (prevState: FinanceCorrectionFormState, formData: FormData) => Promise<FinanceCorrectionFormState>;

export function PrepareFinanceJournalReversalForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Prepare reversal</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit. The original journal must be posted; at most one active reversal per original journal. The system derives the exact
        opposite lines automatically at post time -- never a rewrite of the original.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="rev-originalJournalId" className="text-sm font-medium text-text-primary">
            Original journal ID
          </label>
          <input id="rev-originalJournalId" name="originalJournalId" type="text" required className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rev-correctionDate" className="text-sm font-medium text-text-primary">
            Correction date
          </label>
          <input id="rev-correctionDate" name="correctionDate" type="date" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rev-reason" className="text-sm font-medium text-text-primary">
            Reason
          </label>
          <input id="rev-reason" name="reason" type="text" required className="w-72 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rev-evidenceRef" className="text-sm font-medium text-text-primary">
            Evidence reference (optional)
          </label>
          <input id="rev-evidenceRef" name="evidenceRef" type="text" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rev-idempotencyKey" className="text-sm font-medium text-text-primary">
            Idempotency key
          </label>
          <input id="rev-idempotencyKey" name="idempotencyKey" type="text" required className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Preparing…" className="w-fit">
        Prepare reversal
      </Button>
    </form>
  );
}

export function PrepareFinanceJournalAdjustmentForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Prepare adjustment</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit. The original journal must be posted. Supply the adjustment&apos;s own balanced lines (comma-separated, matching order, at
        least 2 lines) -- debit total must exactly equal credit total, validated before this draft is created.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="adj-originalJournalId" className="text-sm font-medium text-text-primary">
            Original journal ID
          </label>
          <input id="adj-originalJournalId" name="originalJournalId" type="text" required className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="adj-accountIds" className="text-sm font-medium text-text-primary">
            Account IDs (comma-separated)
          </label>
          <input id="adj-accountIds" name="accountIds" type="text" required className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="adj-directions" className="text-sm font-medium text-text-primary">
            Directions (comma-separated)
          </label>
          <input id="adj-directions" name="directions" type="text" required placeholder="debit, credit" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="adj-amounts" className="text-sm font-medium text-text-primary">
            Amounts (comma-separated)
          </label>
          <input id="adj-amounts" name="amounts" type="text" required placeholder="500, 500" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="adj-correctionDate" className="text-sm font-medium text-text-primary">
            Correction date
          </label>
          <input id="adj-correctionDate" name="correctionDate" type="date" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="adj-reason" className="text-sm font-medium text-text-primary">
            Reason
          </label>
          <input id="adj-reason" name="reason" type="text" required className="w-72 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="adj-evidenceRef" className="text-sm font-medium text-text-primary">
            Evidence reference (optional)
          </label>
          <input id="adj-evidenceRef" name="evidenceRef" type="text" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="adj-idempotencyKey" className="text-sm font-medium text-text-primary">
            Idempotency key
          </label>
          <input id="adj-idempotencyKey" name="idempotencyKey" type="text" required className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Preparing…" className="w-fit">
        Prepare adjustment
      </Button>
    </form>
  );
}

export function SubmitFinanceCorrectionForApprovalForm({ action }: { action: BoundAction }) {
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

export function DiscardFinanceCorrectionDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="reason" type="text" placeholder="Reason (optional)" className="w-40 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Discarding…">
        Discard
      </Button>
    </form>
  );
}

export function ApproveFinanceCorrectionForm({ action }: { action: BoundAction }) {
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

export function PostFinanceCorrectionForm({ action }: { action: BoundAction }) {
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
