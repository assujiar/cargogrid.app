"use client";

/** Accounts Receivable client forms (FIN-196, CG-S9-FIN-007). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceArOpenItemFormState, FinanceArExposureLookupFormState } from "./actions.ts";

const INITIAL_STATE: FinanceArOpenItemFormState = { error: null };
const INITIAL_LOOKUP_STATE: FinanceArExposureLookupFormState = { error: null, result: null };

type BoundAction = (prevState: FinanceArOpenItemFormState, formData: FormData) => Promise<FinanceArOpenItemFormState>;
type BoundLookupAction = (prevState: FinanceArExposureLookupFormState, formData: FormData) => Promise<FinanceArExposureLookupFormState>;

export function PlaceFinanceArHoldForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="reason" type="text" placeholder="Hold reason (required)" required className="w-56 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
      <input name="reason" type="text" placeholder="Release reason (optional)" className="w-56 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
        <div className="flex flex-col gap-1">
          <label htmlFor="customerAccountId" className="text-sm font-medium text-text-primary">
            Customer account ID
          </label>
          <input id="customerAccountId" name="customerAccountId" type="text" required className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      {state.result ? (
        <p className="text-sm text-text-primary">
          Total open: <span className="font-semibold">{state.result.totalOpen}</span> across {state.result.openCount} item(s); overdue: <span className="font-semibold">{state.result.overdueOpen}</span> across {state.result.overdueCount} item(s).
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Looking up…" className="w-fit">
        Look up
      </Button>
    </form>
  );
}
