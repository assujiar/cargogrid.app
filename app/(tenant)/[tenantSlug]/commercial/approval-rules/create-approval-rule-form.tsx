"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { QuotationApprovalRuleFormState } from "./actions.ts";

const INITIAL_STATE: QuotationApprovalRuleFormState = { error: null };

/** Client Component wrapper (COM-153) -- same `useActionState`/bound-action split every prior Commercial create-form already uses (mirrors create-margin-rule-form.tsx, COM-150). Every threshold field is optional individually, but the server action rejects a submission with all three blank. */
export function CreateApprovalRuleForm({ action }: { action: (prevState: QuotationApprovalRuleFormState, formData: FormData) => Promise<QuotationApprovalRuleFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a quotation approval rule</h2>
      <p className="text-xs text-neutral-500">
        Requires COM:Create to draft, COM:Approve to publish. Fill in at least one threshold — a quotation crossing any published threshold requires approval before it can be accepted.
      </p>

      <div className="flex flex-col gap-1">
        <label htmlFor="minMarginPct" className="text-sm font-medium text-neutral-700">
          Minimum margin % (below this, approval is required)
        </label>
        <input id="minMarginPct" name="minMarginPct" type="number" min={0} max={100} step="0.01" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="maxDiscountPct" className="text-sm font-medium text-neutral-700">
          Maximum discount % (above this, approval is required)
        </label>
        <input id="maxDiscountPct" name="maxDiscountPct" type="number" min={0} max={100} step="0.01" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="minValueAmount" className="text-sm font-medium text-neutral-700">
          Minimum value (at or above this, approval is required)
        </label>
        <input id="minValueAmount" name="minValueAmount" type="number" min={0} step="0.01" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create approval rule (draft)
      </Button>
    </form>
  );
}
