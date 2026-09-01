"use client";

/** Period Lock and Governed Reopen client forms (FIN-207, CG-S9-FIN-018). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinancePeriodLockFormState } from "./actions.ts";

const INITIAL_STATE: FinancePeriodLockFormState = { error: null };

type BoundAction = (prevState: FinancePeriodLockFormState, formData: FormData) => Promise<FinancePeriodLockFormState>;

export function LockFinancePeriodForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Lock a period scope</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Approve. Locking is idempotent for an already-locked scope, and re-locks a reopened/reopen-requested row in place. Every
        posting service enforces this lock at the database layer, never UI-only.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="w-96">
          <FormField id="lock-periodId" label="Fiscal period ID">
            <Input id="lock-periodId" name="periodId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-32">
          <FormField id="lock-lockScope" label="Lock scope">
            <Select id="lock-lockScope" name="lockScope" required defaultValue="all" invalid={Boolean(state.error)}>
              <option value="all">all</option>
              <option value="gl">gl</option>
              <option value="ar">ar</option>
              <option value="ap">ap</option>
              <option value="tax">tax</option>
            </Select>
          </FormField>
        </div>

        <div className="w-72">
          <FormField id="lock-reason" label="Reason">
            <Input id="lock-reason" name="reason" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-48">
          <FormField id="lock-evidenceRef" label="Evidence reference (optional)">
            <Input id="lock-evidenceRef" name="evidenceRef" type="text" invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Locking…" className="w-fit">
        Lock period
      </Button>
    </form>
  );
}

export function RequestFinancePeriodReopenForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="lock-reopen-reason" className="sr-only">
        Reason
      </label>
      <Input id="lock-reopen-reason" name="reason" type="text" required placeholder="Reason (required)" className="w-40 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Requesting…">
        Request reopen
      </Button>
    </form>
  );
}

export function ApproveFinancePeriodReopenForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="lock-reopen-window" className="sr-only">
        Window (hours)
      </label>
      <Input id="lock-reopen-window" name="windowHours" type="number" min={1} max={720} required placeholder="Window (hours)" className="w-32 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Approving…">
        Approve reopen
      </Button>
    </form>
  );
}

export function RelockFinancePeriodForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Re-locking…">
        Re-lock
      </Button>
    </form>
  );
}
