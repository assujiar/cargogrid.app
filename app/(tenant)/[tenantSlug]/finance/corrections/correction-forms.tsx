"use client";

/** Reversal and Adjustment client forms (FIN-206, CG-S9-FIN-017). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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
        <div className="w-96">
          <FormField id="rev-originalJournalId" label="Original journal ID">
            <Input id="rev-originalJournalId" name="originalJournalId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="rev-correctionDate" label="Correction date">
            <Input id="rev-correctionDate" name="correctionDate" type="date" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-72">
          <FormField id="rev-reason" label="Reason">
            <Input id="rev-reason" name="reason" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="rev-evidenceRef" label="Evidence reference (optional)">
            <Input id="rev-evidenceRef" name="evidenceRef" type="text" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="rev-idempotencyKey" label="Idempotency key">
            <Input id="rev-idempotencyKey" name="idempotencyKey" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
        <div className="w-96">
          <FormField id="adj-originalJournalId" label="Original journal ID">
            <Input id="adj-originalJournalId" name="originalJournalId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-96">
          <FormField id="adj-accountIds" label="Account IDs (comma-separated)">
            <Input id="adj-accountIds" name="accountIds" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="adj-directions" label="Directions (comma-separated)">
            <Input id="adj-directions" name="directions" type="text" required placeholder="debit, credit" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="adj-amounts" label="Amounts (comma-separated)">
            <Input id="adj-amounts" name="amounts" type="text" required placeholder="500, 500" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="adj-correctionDate" label="Correction date">
            <Input id="adj-correctionDate" name="correctionDate" type="date" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-72">
          <FormField id="adj-reason" label="Reason">
            <Input id="adj-reason" name="reason" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="adj-evidenceRef" label="Evidence reference (optional)">
            <Input id="adj-evidenceRef" name="evidenceRef" type="text" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="adj-idempotencyKey" label="Idempotency key">
            <Input id="adj-idempotencyKey" name="idempotencyKey" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      <label htmlFor="discard-correction-reason" className="sr-only">
        Reason
      </label>
      <Input id="discard-correction-reason" name="reason" type="text" placeholder="Reason (optional)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Posting…">
        Post
      </Button>
    </form>
  );
}
