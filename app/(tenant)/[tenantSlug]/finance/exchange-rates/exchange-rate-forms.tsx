"use client";

/** Currency and Exchange Rate client forms (FIN-194, CG-S9-FIN-005). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import type { FinanceExchangeRateFormState, ConvertFinanceAmountFormState } from "./actions.ts";

const INITIAL_STATE: FinanceExchangeRateFormState = { error: null };
const INITIAL_CONVERT_STATE: ConvertFinanceAmountFormState = { error: null, result: null };

type BoundAction = (prevState: FinanceExchangeRateFormState, formData: FormData) => Promise<FinanceExchangeRateFormState>;
type BoundConvertAction = (prevState: ConvertFinanceAmountFormState, formData: FormData) => Promise<ConvertFinanceAmountFormState>;

export function CreateFinanceExchangeRateDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create a draft rate</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Edit. A draft has no effect until approved.</p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="sourceCurrency" className="text-sm font-medium text-text-primary">
            Source currency
          </label>
          <input id="sourceCurrency" name="sourceCurrency" type="text" maxLength={3} placeholder="USD" required className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="targetCurrency" className="text-sm font-medium text-text-primary">
            Target currency
          </label>
          <input id="targetCurrency" name="targetCurrency" type="text" maxLength={3} placeholder="IDR" required className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rateType" className="text-sm font-medium text-text-primary">
            Rate type
          </label>
          <input id="rateType" name="rateType" type="text" defaultValue="spot" className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rate" className="text-sm font-medium text-text-primary">
            Rate
          </label>
          <input id="rate" name="rate" type="number" step="0.0000000001" min="0" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="effectiveFrom" className="text-sm font-medium text-text-primary">
            Effective from
          </label>
          <input id="effectiveFrom" name="effectiveFrom" type="datetime-local" required className="w-56 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="effectiveTo" className="text-sm font-medium text-text-primary">
            Effective to (optional)
          </label>
          <input id="effectiveTo" name="effectiveTo" type="datetime-local" className="w-56 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create draft
      </Button>
    </form>
  );
}

export function DiscardFinanceExchangeRateDraftForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Discarding…">
        Discard
      </Button>
    </form>
  );
}

export function ApproveFinanceExchangeRateForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" loading={pending} loadingLabel="Approving…">
        Approve
      </Button>
    </form>
  );
}

export function ConvertFinanceAmountForm({ action }: { action: BoundConvertAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_CONVERT_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Convert-preview</h2>
      <p className="text-xs text-text-secondary">Requires FIN:View. Read-only -- does not create or change any rate. Same-currency amounts short-circuit without requiring a stored rate.</p>

      <div className="flex flex-wrap gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="convertAmount" className="text-sm font-medium text-text-primary">
            Amount
          </label>
          <input id="convertAmount" name="amount" type="number" step="0.01" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="convertSourceCurrency" className="text-sm font-medium text-text-primary">
            From
          </label>
          <input id="convertSourceCurrency" name="sourceCurrency" type="text" maxLength={3} placeholder="USD" required className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="convertTargetCurrency" className="text-sm font-medium text-text-primary">
            To
          </label>
          <input id="convertTargetCurrency" name="targetCurrency" type="text" maxLength={3} placeholder="IDR" required className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="convertRateType" className="text-sm font-medium text-text-primary">
            Rate type
          </label>
          <input id="convertRateType" name="rateType" type="text" defaultValue="spot" className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      {state.result ? (
        <p className="text-sm text-text-primary">
          {state.result.amount} {state.result.sourceCurrency} = <span className="font-semibold">{state.result.convertedAmount}</span> {state.result.targetCurrency} (rate {state.result.rate}, rounding {state.result.roundingMode})
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Converting…" className="w-fit">
        Convert
      </Button>
    </form>
  );
}
