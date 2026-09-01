"use client";

/** Fiscal Period client forms (FIN-193, CG-S9-FIN-004). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FiscalPeriodFormState } from "./actions.ts";

const INITIAL_STATE: FiscalPeriodFormState = { error: null };

type BoundAction = (prevState: FiscalPeriodFormState, formData: FormData) => Promise<FiscalPeriodFormState>;

export function GenerateFinanceFiscalCalendarForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Generate a fiscal calendar</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Edit. Generates sequential, non-overlapping monthly periods, each pinning your currently-effective close-policy checklist.</p>

      <FormField id="code" label="Calendar code">
        <Input id="code" name="code" type="text" required className="w-48" invalid={Boolean(state.error)} />
      </FormField>

      <FormField id="name" label="Name">
        <Input id="name" name="name" type="text" required className="w-full max-w-md" invalid={Boolean(state.error)} />
      </FormField>

      <FormField id="startDate" label="Start date">
        <Input id="startDate" name="startDate" type="date" required className="w-48" invalid={Boolean(state.error)} />
      </FormField>

      <FormField id="periodCount" label="Number of monthly periods">
        <Input id="periodCount" name="periodCount" type="number" min={1} max={24} defaultValue={12} required className="w-32" invalid={Boolean(state.error)} />
      </FormField>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      <label htmlFor="reopen-period-reason" className="sr-only">
        Reason
      </label>
      <Input id="reopen-period-reason" type="text" name="reason" placeholder="Reason (required)" required className="w-56 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {!satisfied ? null : (
        <>
          <label htmlFor="checklist-item-reason" className="sr-only">
            Reason/evidence
          </label>
          <Input id="checklist-item-reason" type="text" name="reason" placeholder="Reason/evidence" className="w-48 text-xs" invalid={Boolean(state.error)} />
        </>
      )}
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant={satisfied ? "primary" : "secondary"} loading={pending} loadingLabel="Saving…">
        {satisfied ? "Mark satisfied" : "Mark unsatisfied"}
      </Button>
    </form>
  );
}
