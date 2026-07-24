"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { PipelineFormState } from "./actions.ts";

const INITIAL_STATE: PipelineFormState = { error: null };

/** Client Component wrapper (COM-146) -- same `useActionState`/bound-action split `capture-lead-form.tsx` (COM-143) already established. Creates a draft plan; publishing/targets happen on the Plan Detail page. */
export function CreateSalesPlanForm({ action }: { action: (prevState: PipelineFormState, formData: FormData) => Promise<PipelineFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a sales plan</h2>

      <div className="flex flex-col gap-1">
        <label htmlFor="name" className="text-sm font-medium text-neutral-700">
          Plan name
        </label>
        <input id="name" name="name" type="text" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex gap-3">
        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor="periodStart" className="text-sm font-medium text-neutral-700">
            Period start
          </label>
          <input id="periodStart" name="periodStart" type="date" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor="periodEnd" className="text-sm font-medium text-neutral-700">
            Period end
          </label>
          <input id="periodEnd" name="periodEnd" type="date" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="orgUnitId" className="text-sm font-medium text-neutral-700">
          Organization unit ID <span className="font-normal text-neutral-500">(optional -- leave blank for a tenant-wide plan)</span>
        </label>
        <input id="orgUnitId" name="orgUnitId" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create plan
      </Button>
    </form>
  );
}
