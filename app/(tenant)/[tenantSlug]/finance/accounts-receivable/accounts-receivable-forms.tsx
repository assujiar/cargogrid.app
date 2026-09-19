"use client";

/** Accounts Receivable client forms (FIN-196, CG-S9-FIN-007). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceArOpenItemFormState, FinanceArExposureLookupFormState } from "./actions.ts";

const INITIAL_STATE: FinanceArOpenItemFormState = { error: null };
const INITIAL_LOOKUP_STATE: FinanceArExposureLookupFormState = { error: null, result: null };

type BoundAction = (prevState: FinanceArOpenItemFormState, formData: FormData) => Promise<FinanceArOpenItemFormState>;
type BoundLookupAction = (prevState: FinanceArExposureLookupFormState, formData: FormData) => Promise<FinanceArExposureLookupFormState>;

export function PlaceFinanceArHoldForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="ar-hold-reason" className="sr-only">
        Hold reason
      </label>
      <Input id="ar-hold-reason" name="reason" type="text" placeholder="Hold reason (required)" required className="w-56 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Placing hold…">
        Place hold
      </Button>
    </form>
  );
}

export function ReleaseFinanceArHoldForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="ar-release-reason" className="sr-only">
        Release reason
      </label>
      <Input id="ar-release-reason" name="reason" type="text" placeholder="Release reason (optional)" className="w-56 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Releasing…">
        Release hold (FIN:Approve)
      </Button>
    </form>
  );
}

export function FinanceArExposureLookupForm({ action }: { action: BoundLookupAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_LOOKUP_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Customer credit exposure</h2>
      <p className="text-xs text-text-secondary">Requires FIN:View. Internal Finance aggregate only -- customer-facing visibility is deferred to Step 13.</p>

      <div className="flex flex-wrap gap-3">
        <div className="w-96">
          <FormField id="customerAccountId" label="Customer account ID">
            <Input id="customerAccountId" name="customerAccountId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      {state.result ? (
        state.result.length === 0 ? (
          <p className="text-sm text-text-secondary">No open items for this customer.</p>
        ) : (
          <ul className="flex flex-col gap-1 text-sm text-text-primary">
            {state.result.map((row) => (
              <li key={row.currency}>
                <span className="font-semibold">{row.currency}</span>: total open <span className="font-semibold">{row.totalOpen}</span> across {row.openCount} item(s); overdue{" "}
                <span className="font-semibold">{row.overdueOpen}</span> across {row.overdueCount} item(s).
                {row.fxStatus === "identity" ? null : row.fxStatus === "converted" ? (
                  <span className="text-text-secondary"> (≈ {row.baseTotalOpen} {row.baseCurrency})</span>
                ) : (
                  <span className="text-text-secondary"> (no {row.baseCurrency} exchange rate available to convert)</span>
                )}
              </li>
            ))}
          </ul>
        )
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Looking up…" className="w-fit">
        Look up
      </Button>
    </form>
  );
}
