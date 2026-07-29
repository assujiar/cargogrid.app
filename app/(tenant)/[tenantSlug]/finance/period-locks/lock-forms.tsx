"use client";

/** Period Lock and Governed Reopen client forms (FIN-207, CG-S9-FIN-018). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
        <div className="flex flex-col gap-1">
          <label htmlFor="lock-periodId" className="text-sm font-medium text-text-primary">
            Fiscal period ID
          </label>
          <input id="lock-periodId" name="periodId" type="text" required className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="lock-lockScope" className="text-sm font-medium text-text-primary">
            Lock scope
          </label>
          <select id="lock-lockScope" name="lockScope" required defaultValue="all" className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="all">all</option>
            <option value="gl">gl</option>
            <option value="ar">ar</option>
            <option value="ap">ap</option>
            <option value="tax">tax</option>
          </select>
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="lock-reason" className="text-sm font-medium text-text-primary">
            Reason
          </label>
          <input id="lock-reason" name="reason" type="text" required className="w-72 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="lock-evidenceRef" className="text-sm font-medium text-text-primary">
            Evidence reference (optional)
          </label>
          <input id="lock-evidenceRef" name="evidenceRef" type="text" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

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
      <input name="reason" type="text" required placeholder="Reason (required)" className="w-40 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      <input name="windowHours" type="number" min={1} max={720} required placeholder="Window (hours)" className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Re-locking…">
        Re-lock
      </Button>
    </form>
  );
}
