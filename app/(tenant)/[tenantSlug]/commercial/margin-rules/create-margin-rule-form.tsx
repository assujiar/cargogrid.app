"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { MarginRuleFormState } from "./actions.ts";

const INITIAL_STATE: MarginRuleFormState = { error: null };

/** Client Component wrapper (COM-150) -- same `useActionState`/bound-action split every prior Commercial create-form already uses. */
export function CreateMarginRuleForm({ action }: { action: (prevState: MarginRuleFormState, formData: FormData) => Promise<MarginRuleFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  const describedBy = state.error ? "margin-rule-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a margin rule</h2>
      <p className="text-xs text-neutral-500">Requires COM:Create to draft, COM:Approve to publish -- a role lacking either will see a denial here, which is expected.</p>

      <FormField id="minimumMarginPct" label="Minimum margin %">
        <div className="w-32">
          <NumberInput id="minimumMarginPct" name="minimumMarginPct" min={0} max={100} step="0.01" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </div>
      </FormField>

      <FormField id="roundingMode" label="Rounding mode">
        <div className="w-48">
          <Select id="roundingMode" name="roundingMode" defaultValue="half_up" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="half_up">Half up</option>
            <option value="half_even">Half even</option>
            <option value="floor">Floor</option>
            <option value="ceiling">Ceiling</option>
          </Select>
        </div>
      </FormField>

      {state.error ? <ValidationMessage id="margin-rule-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create margin rule (draft)
      </Button>
    </form>
  );
}
