"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { JobProfitabilityDirectoryRow } from "../../../../../../server/contracts/job-profitability/job-profitability.ts";
import type { JobOrderFormState } from "./actions.ts";

const INITIAL_STATE: JobOrderFormState = { error: null };

/** OPS-179: an operational (never accounting P&L) margin snapshot -- masked entirely without OPS:View margin, otherwise shows revenue/cost/margin plus a recalculate action (reason required once a snapshot already exists). */
export function JobProfitabilityPanel({
  snapshot,
  action,
}: {
  readonly snapshot: JobProfitabilityDirectoryRow | null;
  readonly action: (prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState>;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-3">
      <p className="text-xs text-neutral-500">Operational margin only -- not accounting P&amp;L or recognized revenue.</p>
      {/* ISS-2026-197: revenue_basis is metadata, never masked -- shown regardless of margin_masked/status so a viewer can never mistake this quote-time figure for a billed one. */}
      {snapshot ? <p className="text-xs text-neutral-500">Revenue basis: quoted (quote-time estimate, not billed -- see Finance profitability for the billed figure).</p> : null}

      {!snapshot ? (
        <p className="text-sm text-neutral-500">No profitability snapshot has been calculated yet.</p>
      ) : snapshot.marginMasked ? (
        <p className="text-sm text-neutral-500">Restricted -- OPS:View margin is required to see this Job Order&apos;s profitability.</p>
      ) : snapshot.status === "unavailable" ? (
        <div className="flex items-center gap-2">
          <StatusBadge tone="warning" label="Unavailable" />
          <span className="text-sm text-neutral-600">{snapshot.blockedReason}</span>
        </div>
      ) : (
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Revenue ({snapshot.revenueBasis})</dt>
          <dd className="text-neutral-900">
            {snapshot.revenueAmount?.toLocaleString()} {snapshot.revenueCurrency}
          </dd>
          <dt className="text-neutral-600">Actual cost</dt>
          <dd className="text-neutral-900">
            {snapshot.costAmount?.toLocaleString()} {snapshot.costCurrency}
          </dd>
          <dt className="text-neutral-600">Margin</dt>
          <dd className="text-neutral-900">
            {snapshot.marginAmount?.toLocaleString()} {snapshot.revenueCurrency} ({snapshot.marginPercent}%)
          </dd>
          <dt className="text-neutral-600">Version</dt>
          <dd className="text-neutral-900">v{snapshot.versionNumber}</dd>
        </dl>
      )}

      <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
        {snapshot ? (
          <FormField id="recalculationReason" label="Recalculation reason (required to recalculate)">
            <Input
              id="recalculationReason"
              type="text"
              name="recalculationReason"
              invalid={Boolean(state.error)}
              aria-describedby={state.error ? "job-profitability-error" : undefined}
            />
          </FormField>
        ) : null}
        <Button type="submit" loading={pending} loadingLabel="Calculating…" variant="secondary">
          {snapshot ? "Recalculate" : "Calculate profitability"}
        </Button>
      </form>
      {state.error ? <ValidationMessage id="job-profitability-error">{state.error}</ValidationMessage> : null}
    </div>
  );
}
