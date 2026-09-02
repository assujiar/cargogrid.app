"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { PipelineFormState } from "./actions.ts";
import { Input } from "../../../../../components/forms/input.tsx";
import { DateInput } from "../../../../../components/forms/date-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";

const INITIAL_STATE: PipelineFormState = { error: null };

/** Client Component wrapper (COM-146) -- same `useActionState`/bound-action split `capture-lead-form.tsx` (COM-143) already established. Creates a draft plan; publishing/targets happen on the Plan Detail page. */
export function CreateSalesPlanForm({ action }: { action: (prevState: PipelineFormState, formData: FormData) => Promise<PipelineFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  const describedBy = state.error ? "create-sales-plan-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a sales plan</h2>

      <FormField id="name" label="Plan name">
        <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <div className="flex gap-3">
        <div className="flex-1">
          <FormField id="periodStart" label="Period start">
            <DateInput id="periodStart" name="periodStart" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="flex-1">
          <FormField id="periodEnd" label="Period end">
            <DateInput id="periodEnd" name="periodEnd" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      <FormField
        id="orgUnitId"
        label={
          <>
            Organization unit ID <span className="font-normal text-neutral-500">(optional -- leave blank for a tenant-wide plan)</span>
          </>
        }
      >
        <Input id="orgUnitId" name="orgUnitId" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      {state.error ? <ValidationMessage id="create-sales-plan-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create plan
      </Button>
    </form>
  );
}
