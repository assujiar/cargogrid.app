"use client";

/** Job, Customer and Service Profitability client forms (FIN-212, CG-S9-FIN-023). Same `useActionState`/bound-action split every prior capability's own forms already use. */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { FINANCE_JOB_PROFITABILITY_STATUS_TONE_MAP } from "../../../../../components/domain/status-tone-map.ts";
import type { FinanceProfitabilityFormState } from "./actions.ts";

const INITIAL_STATE: FinanceProfitabilityFormState = { error: null, fact: null };

type BoundAction = (prevState: FinanceProfitabilityFormState, formData: FormData) => Promise<FinanceProfitabilityFormState>;

export function CalculateFinanceJobProfitabilityForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-text-primary">Calculate Job Order profitability</h2>
      <p className="text-xs text-text-secondary">
        Requires FIN:Edit and FIN:View margin. Resolves billed revenue (every issued invoice for the Job Order) minus approved actual cost --
        reports a named blocked reason (<code>no_billed_revenue</code>, <code>no_approved_cost</code>, or <code>mixed_currency</code>) rather than
        a fabricated figure. The first calculation needs no reason; recalculating an existing fact requires one.
      </p>

      <div className="flex flex-wrap gap-3">
        <div className="w-80">
          <FormField id="profitability-jobOrderId" label="Job Order id">
            <Input id="profitability-jobOrderId" name="jobOrderId" type="text" required className="font-mono text-xs" invalid={Boolean(state.error)} />
          </FormField>
        </div>

        <div className="flex-1">
          <FormField id="profitability-recalculationReason" label="Recalculation reason (only required if a fact already exists)">
            <Input id="profitability-recalculationReason" name="recalculationReason" type="text" invalid={Boolean(state.error)} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}

      {state.fact ? (
        <dl className="grid grid-cols-2 gap-2 rounded-md border border-neutral-200 p-3 text-sm sm:grid-cols-4">
          <dt className="text-text-secondary">Status</dt>
          <dd>
            <StatusBadge tone={FINANCE_JOB_PROFITABILITY_STATUS_TONE_MAP[state.fact.status].tone} label={FINANCE_JOB_PROFITABILITY_STATUS_TONE_MAP[state.fact.status].label} />
          </dd>
          <dt className="text-text-secondary">Blocked reason</dt>
          <dd>{state.fact.blockedReason ?? "-"}</dd>
          <dt className="text-text-secondary">Revenue ({state.fact.revenueBasis})</dt>
          <dd>
            {state.fact.revenueAmount ?? "-"} {state.fact.revenueCurrency ?? ""}
          </dd>
          <dt className="text-text-secondary">Cost</dt>
          <dd>
            {state.fact.costAmount ?? "-"} {state.fact.costCurrency ?? ""}
          </dd>
          <dt className="text-text-secondary">Profit</dt>
          <dd>{state.fact.profitAmount ?? "-"}</dd>
          <dt className="text-text-secondary">Margin %</dt>
          <dd>{state.fact.marginPercent === null ? "-" : `${state.fact.marginPercent}%`}</dd>
          <dt className="text-text-secondary">Version</dt>
          <dd>{state.fact.versionNumber}</dd>
        </dl>
      ) : null}

      <Button type="submit" loading={pending} loadingLabel="Calculating…" className="w-fit">
        Calculate
      </Button>
    </form>
  );
}
