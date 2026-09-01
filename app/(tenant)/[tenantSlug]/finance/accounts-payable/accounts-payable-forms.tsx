"use client";

/** Accounts Payable client forms (FIN-199, CG-S9-FIN-010). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceApOpenItemFormState, FinanceApExposureLookupFormState } from "./actions.ts";

const INITIAL_STATE: FinanceApOpenItemFormState = { error: null };
const INITIAL_LOOKUP_STATE: FinanceApExposureLookupFormState = { error: null, result: null };

type BoundAction = (prevState: FinanceApOpenItemFormState, formData: FormData) => Promise<FinanceApOpenItemFormState>;
type BoundLookupAction = (prevState: FinanceApExposureLookupFormState, formData: FormData) => Promise<FinanceApExposureLookupFormState>;

export function PlaceFinanceApHoldForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="ap-hold-reason" className="sr-only">
        Hold reason
      </label>
      <Input id="ap-hold-reason" name="reason" type="text" placeholder="Hold reason (required)" required className="w-56 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Placing hold…">
        Place hold
      </Button>
    </form>
  );
}

export function ReleaseFinanceApHoldForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="ap-release-reason" className="sr-only">
        Release reason
      </label>
      <Input id="ap-release-reason" name="reason" type="text" placeholder="Release reason (optional)" className="w-56 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Releasing…">
        Release hold (FIN:Approve)
      </Button>
    </form>
  );
}

export function FinanceApExposureLookupForm({ action }: { action: BoundLookupAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_LOOKUP_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Vendor obligation exposure</h2>
      <p className="text-xs text-text-secondary">Requires FIN:View. Internal Finance aggregate only.</p>

      <div className="flex flex-wrap gap-3">
        <div className="w-96">
          <FormField id="vendorMasterId" label="Vendor reference ID">
            <Input id="vendorMasterId" name="vendorMasterId" type="text" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
