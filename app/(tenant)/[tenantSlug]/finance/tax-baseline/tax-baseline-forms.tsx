"use client";

/** Tax Baseline client forms (FIN-195, CG-S9-FIN-006). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { FinanceTaxRuleFormState, CalculateFinanceTaxFormState } from "./actions.ts";
import type { FinanceTaxCode } from "../../../../../server/contracts/tax-baseline/tax-baseline.ts";

const INITIAL_STATE: FinanceTaxRuleFormState = { error: null };
const INITIAL_CALCULATE_STATE: CalculateFinanceTaxFormState = { error: null, result: null };

type BoundAction = (prevState: FinanceTaxRuleFormState, formData: FormData) => Promise<FinanceTaxRuleFormState>;
type BoundCalculateAction = (prevState: CalculateFinanceTaxFormState, formData: FormData) => Promise<CalculateFinanceTaxFormState>;

export function CreateFinanceTaxRuleDraftForm({ action, taxCodes }: { action: BoundAction; taxCodes: readonly FinanceTaxCode[] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Create a draft tax rule</h2>
      <p className="text-xs text-text-secondary">Requires FIN:Edit. No rate/rule may be invented -- attach real SME evidence before requesting approval. A draft has no calculation effect until an authorized SME approves it.</p>

      <div className="flex flex-wrap gap-3">
        <div className="w-64">
          <FormField id="taxCodeId" label="Tax code">
            <Select id="taxCodeId" name="taxCodeId" required invalid={Boolean(state.error)}>
              <option value="">Select a tax code…</option>
              {taxCodes.map((code) => (
                <option key={code.id} value={code.id}>
                  {code.code} — {code.name}
                </option>
              ))}
            </Select>
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="rateBasis" label="Rate basis">
            <Select id="rateBasis" name="rateBasis" defaultValue="percentage" invalid={Boolean(state.error)}>
              <option value="percentage">Percentage</option>
              <option value="fixed_amount">Fixed amount</option>
            </Select>
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="rateValue" label="Rate value">
            <Input id="rateValue" name="rateValue" type="number" step="0.000001" min="0" required invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-44">
          <FormField id="effectiveFrom" label="Effective from">
            <Input id="effectiveFrom" name="effectiveFrom" type="date" required invalid={Boolean(state.error)} />
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

export function AttachFinanceTaxRuleEvidenceForm({ action }: { action: (prevState: FinanceTaxRuleFormState, formData: FormData) => Promise<FinanceTaxRuleFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <label htmlFor="evidence-note" className="sr-only">
        SME evidence note / reference
      </label>
      <Input id="evidence-note" name="evidenceNote" type="text" placeholder="SME evidence note / reference" required className="w-56 text-xs" invalid={Boolean(state.error)} />
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Attaching…">
        Attach evidence
      </Button>
    </form>
  );
}

export function DiscardFinanceTaxRuleDraftForm({ action }: { action: BoundAction }) {
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

export function ApproveFinanceTaxRuleForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" loading={pending} loadingLabel="Approving…">
        Approve (SME)
      </Button>
    </form>
  );
}

export function CalculateFinanceTaxForm({ action }: { action: BoundCalculateAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_CALCULATE_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Calculate-preview</h2>
      <p className="text-xs text-text-secondary">Requires FIN:View. Read-only. Rejected -- never silently zero -- when no approved rule covers this tax code.</p>

      <div className="flex flex-wrap gap-3">
        <div className="w-32">
          <FormField id="calc-taxCode" label="Tax code">
            <Input id="calc-taxCode" name="taxCode" type="text" placeholder="PPN" required className="uppercase" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="w-40">
          <FormField id="baseAmount" label="Base amount">
            <Input id="baseAmount" name="baseAmount" type="number" step="0.01" min="0" required invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      {state.result ? (
        <p className="text-sm text-text-primary">
          {state.result.baseAmount} × {state.result.taxCode} ({state.result.rateBasis} {state.result.rateValue}) = <span className="font-semibold">{state.result.taxAmount}</span> (rounding {state.result.roundingMode})
        </p>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Calculating…" className="w-fit">
        Calculate
      </Button>
    </form>
  );
}
