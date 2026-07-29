"use client";

/** AR and AP Aging client forms (FIN-210, CG-S9-FIN-021). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceAgingFormState } from "./actions.ts";

const INITIAL_STATE: FinanceAgingFormState = { error: null };

type BoundAction = (prevState: FinanceAgingFormState, formData: FormData) => Promise<FinanceAgingFormState>;

export function SetFinanceAgingBucketConfigForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Set aging bucket configuration</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Approve -- bucket boundaries are a governance decision, not a routine edit. Buckets must be non-overlapping, contiguous,
        start at or before zero days overdue, and end with exactly one open-ended (<code>maxDays: null</code>) bucket. Writing a new
        configuration never edits a prior version -- it is versioned automatically.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="aging-entityType" className="text-sm font-medium text-text-primary">
            Entity type
          </label>
          <select id="aging-entityType" name="entityType" required defaultValue="ar" className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="ar">ar</option>
            <option value="ap">ap</option>
          </select>
        </div>

        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor="aging-bucketsJson" className="text-sm font-medium text-text-primary">
            Buckets (JSON array)
          </label>
          <textarea
            id="aging-bucketsJson"
            name="bucketsJson"
            required
            rows={3}
            placeholder='[{"label":"Current","minDays":-999999,"maxDays":0},{"label":"1-30","minDays":1,"maxDays":30},{"label":"31+","minDays":31,"maxDays":null}]'
            className="w-full rounded-md border border-neutral-300 px-3 py-2 font-mono text-xs"
          />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Saving…" className="w-fit">
        Save bucket configuration
      </Button>
    </form>
  );
}
