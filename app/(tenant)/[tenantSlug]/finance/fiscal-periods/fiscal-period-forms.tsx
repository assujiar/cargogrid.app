"use client";

/** Fiscal Period client forms (FIN-193, CG-S9-FIN-004). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FiscalPeriodFormState } from "./actions.ts";

const INITIAL_STATE: FiscalPeriodFormState = { error: null };

type BoundAction = (prevState: FiscalPeriodFormState, formData: FormData) => Promise<FiscalPeriodFormState>;

export function GenerateFinanceFiscalCalendarForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Generate a fiscal calendar</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Edit. Generates sequential, non-overlapping monthly periods, each pinning your currently-effective close-policy checklist.</p>

      <div className="flex flex-col gap-1">
        <label htmlFor="code" className="text-sm font-medium text-text-primary">
          Calendar code
        </label>
        <input id="code" name="code" type="text" required className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="name" className="text-sm font-medium text-text-primary">
          Name
        </label>
        <input id="name" name="name" type="text" required className="w-full max-w-md rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="startDate" className="text-sm font-medium text-text-primary">
          Start date
        </label>
        <input id="startDate" name="startDate" type="date" required className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="periodCount" className="text-sm font-medium text-text-primary">
          Number of monthly periods
        </label>
        <input id="periodCount" name="periodCount" type="number" min={1} max={24} defaultValue={12} required className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Generating…" className="w-fit">
        Generate calendar
      </Button>
    </form>
  );
}

export function SoftCloseFinancePeriodForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Soft-closing…">
        Soft-close
      </Button>
    </form>
  );
}

export function CloseFinancePeriodForm({ action, disabled }: { action: BoundAction; disabled?: boolean }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Closing…" disabled={disabled}>
        Close
      </Button>
      {disabled ? <p className="text-xs text-text-secondary">Not ready -- unsatisfied required checklist item(s) remain.</p> : null}
    </form>
  );
}

export function ReopenFinancePeriodForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input type="text" name="reason" placeholder="Reason (required)" required className="w-56 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reopening…">
        Reopen (governed)
      </Button>
    </form>
  );
}

export function AcknowledgeChecklistItemForm({ action, satisfied }: { action: BoundAction; satisfied: boolean }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input type="hidden" name="satisfied" value={satisfied ? "true" : "false"} />
      {!satisfied ? null : <input type="text" name="reason" placeholder="Reason/evidence" className="w-48 rounded-md border border-neutral-300 px-2 py-1 text-xs" />}
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant={satisfied ? "primary" : "secondary"} loading={pending} loadingLabel="Saving…">
        {satisfied ? "Mark satisfied" : "Mark unsatisfied"}
      </Button>
    </form>
  );
}
