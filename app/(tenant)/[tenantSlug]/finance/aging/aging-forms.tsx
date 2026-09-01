"use client";

/** AR and AP Aging client forms (FIN-210, CG-S9-FIN-021). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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
        <div className="w-24">
          <FormField id="aging-entityType" label="Entity type">
            <Select id="aging-entityType" name="entityType" required defaultValue="ar" invalid={Boolean(state.error)}>
              <option value="ar">ar</option>
              <option value="ap">ap</option>
            </Select>
          </FormField>
        </div>

        <div className="flex-1">
          <FormField id="aging-bucketsJson" label="Buckets (JSON array)">
            <Textarea
              id="aging-bucketsJson"
              name="bucketsJson"
              required
              rows={3}
              placeholder='[{"label":"Current","minDays":-999999,"maxDays":0},{"label":"1-30","minDays":1,"maxDays":30},{"label":"31+","minDays":31,"maxDays":null}]'
              className="font-mono text-xs"
              invalid={Boolean(state.error)}
            />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Saving…" className="w-fit">
        Save bucket configuration
      </Button>
    </form>
  );
}
