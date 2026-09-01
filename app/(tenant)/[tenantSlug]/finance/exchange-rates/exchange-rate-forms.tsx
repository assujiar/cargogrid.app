"use client";

/** Currency and Exchange Rate client forms (FIN-194, CG-S9-FIN-005). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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
        <div className="w-24">
          <FormField id="sourceCurrency" label="Source currency">
            <Input id="sourceCurrency" name="sourceCurrency" type="text" maxLength={3} placeholder="USD" required className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-24">
          <FormField id="targetCurrency" label="Target currency">
            <Input id="targetCurrency" name="targetCurrency" type="text" maxLength={3} placeholder="IDR" required className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-32">
          <FormField id="rateType" label="Rate type">
            <Input id="rateType" name="rateType" type="text" defaultValue="spot" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="rate" label="Rate">
            <Input id="rate" name="rate" type="number" step="0.0000000001" min="0" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      <div className="flex flex-wrap gap-3">
        <div className="w-56">
          <FormField id="effectiveFrom" label="Effective from">
            <Input id="effectiveFrom" name="effectiveFrom" type="datetime-local" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-56">
          <FormField id="effectiveTo" label="Effective to (optional)">
            <Input id="effectiveTo" name="effectiveTo" type="datetime-local" invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
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
        <div className="w-40">
          <FormField id="convertAmount" label="Amount">
            <Input id="convertAmount" name="amount" type="number" step="0.01" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-24">
          <FormField id="convertSourceCurrency" label="From">
            <Input id="convertSourceCurrency" name="sourceCurrency" type="text" maxLength={3} placeholder="USD" required className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-24">
          <FormField id="convertTargetCurrency" label="To">
            <Input id="convertTargetCurrency" name="targetCurrency" type="text" maxLength={3} placeholder="IDR" required className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-32">
          <FormField id="convertRateType" label="Rate type">
            <Input id="convertRateType" name="rateType" type="text" defaultValue="spot" invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

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
