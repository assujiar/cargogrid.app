"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { QuotationApprovalRuleFormState } from "./actions.ts";

const INITIAL_STATE: QuotationApprovalRuleFormState = { error: null };

/** Client Component wrapper (COM-153) -- same `useActionState`/bound-action split every prior Commercial create-form already uses (mirrors create-margin-rule-form.tsx, COM-150). Every threshold field is optional individually, but the server action rejects a submission with all three blank. */
export function CreateApprovalRuleForm({ action }: { action: (prevState: QuotationApprovalRuleFormState, formData: FormData) => Promise<QuotationApprovalRuleFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  // The action's one error covers the three thresholds together ("fill in at least one"),
  // so every field points at the shared message rather than claiming a per-field fault.
  const describedBy = state.error ? "approval-rule-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a quotation approval rule</h2>
      <p className="text-xs text-neutral-500">
        Requires COM:Create to draft, COM:Approve to publish. Fill in at least one threshold — a quotation crossing any published threshold requires approval before it can be accepted.
      </p>

      <FormField id="minMarginPct" label="Minimum margin % (below this, approval is required)">
        <div className="w-48">
          <NumberInput id="minMarginPct" name="minMarginPct" min={0} max={100} step="0.01" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </div>
      </FormField>

      <FormField id="maxDiscountPct" label="Maximum discount % (above this, approval is required)">
        <div className="w-48">
          <NumberInput id="maxDiscountPct" name="maxDiscountPct" min={0} max={100} step="0.01" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </div>
      </FormField>

      <FormField id="minValueAmount" label="Minimum value (at or above this, approval is required)">
        <div className="w-48">
          <NumberInput id="minValueAmount" name="minValueAmount" min={0} step="0.01" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </div>
      </FormField>

      {state.error ? <ValidationMessage id="approval-rule-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create approval rule (draft)
      </Button>
    </form>
  );
}
