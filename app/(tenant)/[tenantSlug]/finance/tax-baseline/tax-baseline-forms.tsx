"use client";

/** Tax Baseline client forms (FIN-195, CG-S9-FIN-006). Same `useActionState`/bound-action split every prior capability's own create-form already uses. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
        <div className="flex flex-col gap-1">
          <label htmlFor="taxCodeId" className="text-sm font-medium text-text-primary">
            Tax code
          </label>
          <select id="taxCodeId" name="taxCodeId" required className="w-64 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="">Select a tax code…</option>
            {taxCodes.map((code) => (
              <option key={code.id} value={code.id}>
                {code.code} — {code.name}
              </option>
            ))}
          </select>
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rateBasis" className="text-sm font-medium text-text-primary">
            Rate basis
          </label>
          <select id="rateBasis" name="rateBasis" defaultValue="percentage" className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm">
            <option value="percentage">Percentage</option>
            <option value="fixed_amount">Fixed amount</option>
          </select>
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="rateValue" className="text-sm font-medium text-text-primary">
            Rate value
          </label>
          <input id="rateValue" name="rateValue" type="number" step="0.000001" min="0" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="effectiveFrom" className="text-sm font-medium text-text-primary">
            Effective from
          </label>
          <input id="effectiveFrom" name="effectiveFrom" type="date" required className="w-44 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
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

export function AttachFinanceTaxRuleEvidenceForm({ action }: { action: (prevState: FinanceTaxRuleFormState, formData: FormData) => Promise<FinanceTaxRuleFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      <input name="evidenceNote" type="text" placeholder="SME evidence note / reference" required className="w-56 rounded-md border border-neutral-300 px-2 py-1 text-xs" />
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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

export function ApproveFinanceTaxRuleForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1" noValidate>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
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
        <div className="flex flex-col gap-1">
          <label htmlFor="taxCode" className="text-sm font-medium text-text-primary">
            Tax code
          </label>
          <input id="taxCode" name="taxCode" type="text" placeholder="PPN" required className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm uppercase" />
        </div>

        <div className="flex flex-col gap-1">
          <label htmlFor="baseAmount" className="text-sm font-medium text-text-primary">
            Base amount
          </label>
          <input id="baseAmount" name="baseAmount" type="number" step="0.01" min="0" required className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

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
