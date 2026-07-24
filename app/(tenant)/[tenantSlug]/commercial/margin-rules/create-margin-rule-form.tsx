"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { MarginRuleFormState } from "./actions.ts";

const INITIAL_STATE: MarginRuleFormState = { error: null };

/** Client Component wrapper (COM-150) -- same `useActionState`/bound-action split every prior Commercial create-form already uses. */
export function CreateMarginRuleForm({ action }: { action: (prevState: MarginRuleFormState, formData: FormData) => Promise<MarginRuleFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Create a margin rule</h2>
      <p className="text-xs text-neutral-500">Requires COM:Create to draft, COM:Approve to publish -- a role lacking either will see a denial here, which is expected.</p>

      <div className="flex flex-col gap-1">
        <label htmlFor="minimumMarginPct" className="text-sm font-medium text-neutral-700">Minimum margin %</label>
        <input id="minimumMarginPct" name="minimumMarginPct" type="number" min={0} max={100} step="0.01" required className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex flex-col gap-1">
        <label htmlFor="roundingMode" className="text-sm font-medium text-neutral-700">Rounding mode</label>
        <select id="roundingMode" name="roundingMode" defaultValue="half_up" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="half_up">Half up</option>
          <option value="half_even">Half even</option>
          <option value="floor">Floor</option>
          <option value="ceiling">Ceiling</option>
        </select>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…">
        Create margin rule (draft)
      </Button>
    </form>
  );
}
