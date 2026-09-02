"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { calculateMarginAction, overrideMarginThresholdAction } from "./actions.ts";
import type { MarginCalculation } from "../../../../../../server/contracts/margin/margin.ts";
import type { RateSelection } from "../../../../../../server/contracts/rate/rate.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/**
 * Margin calculation trigger + override panel (COM-150). Requires both COM:Edit and
 * COM:View cost to calculate (mirrors app.submit_costing_response's own dual gate) --
 * the underlying app.calculate_margin RPC enforces this regardless of what this form
 * sends. Recalculating for the same rate selection supersedes the prior current result
 * rather than editing it in place.
 */
export function CalculateMarginForm({
  tenantSlug,
  requestId,
  rateSelections,
  currentCalculation,
}: {
  tenantSlug: string;
  requestId: string;
  rateSelections: readonly RateSelection[];
  currentCalculation: MarginCalculation | null;
}) {
  const [rateSelectionId, setRateSelectionId] = useState(rateSelections[0]?.id ?? "");
  const [sellAmount, setSellAmount] = useState("");
  const [sellCurrency, setSellCurrency] = useState("");
  const [discountPct, setDiscountPct] = useState("0");
  const [overrideReason, setOverrideReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  // The calculate and the override actions share one `error` slot, so no field can
  // honestly claim `aria-invalid`; every control instead points at the shared message
  // (ISS-2026-242's own documented multi-action case). The message itself only renders
  // inside the `rateSelections.length > 0` branch (unchanged from before this retrofit),
  // so `aria-describedby` is only emitted when that element really is on the page.
  const describedBy = rateSelections.length > 0 && error ? "margin-error" : undefined;

  const needsOverride = currentCalculation?.thresholdOutcome === "requires_approval" && !currentCalculation.isOverridden;

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Margin calculation</h2>

      {rateSelections.length === 0 ? (
        <p className="text-sm text-neutral-600">Select a rate above before calculating a margin.</p>
      ) : (
        <>
          <FormField id="margin-rate-selection" label={<span className="sr-only">Rate selection</span>}>
            <Select id="margin-rate-selection" value={rateSelectionId} onChange={(e) => setRateSelectionId(e.target.value)} aria-describedby={describedBy}>
              {rateSelections.map((selection) => (
                <option key={selection.id} value={selection.id}>
                  {selection.isAdhoc ? "Ad-hoc selection" : "Catalog selection"} ({selection.id.slice(0, 8)})
                </option>
              ))}
            </Select>
          </FormField>
          <div className="flex gap-2">
            <div className="w-40">
              <FormField id="margin-sell-amount" label={<span className="sr-only">Sell amount</span>}>
                <Input type="number" inputMode="decimal" id="margin-sell-amount" min={0} placeholder="Sell amount" value={sellAmount} onChange={(e) => setSellAmount(e.target.value)} aria-describedby={describedBy} />
              </FormField>
            </div>
            <div className="w-32">
              <FormField id="margin-sell-currency" label={<span className="sr-only">Currency</span>}>
                <Input id="margin-sell-currency" placeholder="Currency (e.g. IDR)" value={sellCurrency} onChange={(e) => setSellCurrency(e.target.value.toUpperCase())} aria-describedby={describedBy} />
              </FormField>
            </div>
            <div className="w-28">
              <FormField id="margin-discount-pct" label={<span className="sr-only">Discount %</span>}>
                <NumberInput id="margin-discount-pct" min={0} max={100} placeholder="Discount %" value={discountPct} onChange={(e) => setDiscountPct(e.target.value)} aria-describedby={describedBy} />
              </FormField>
            </div>
          </div>

          {error ? <ValidationMessage id="margin-error">{error}</ValidationMessage> : null}

          <Button
            type="button"
            disabled={!rateSelectionId || !sellAmount.trim() || !/^[A-Z]{3}$/.test(sellCurrency)}
            loading={pending}
            loadingLabel="Calculating…"
            onClick={() =>
              startTransition(async () => {
                const result = await calculateMarginAction(tenantSlug, requestId, rateSelectionId, Number(sellAmount), sellCurrency, Number(discountPct) || 0);
                setError(result.error);
              })
            }
          >
            Calculate margin
          </Button>
        </>
      )}

      {currentCalculation ? (
        <div className="mt-2 border-t border-neutral-100 pt-2 text-sm">
          <p className="text-neutral-900">
            {currentCalculation.marginPct === null ? "Restricted" : `Margin: ${currentCalculation.marginPct}%`} — {currentCalculation.thresholdOutcome}
            {currentCalculation.isOverridden ? " (overridden)" : ""}
          </p>
          {needsOverride ? (
            <div className="mt-2 flex flex-col gap-2">
              <FormField id="margin-override-reason" label={<span className="sr-only">Override reason</span>}>
                <Input id="margin-override-reason" placeholder="Override reason" value={overrideReason} onChange={(e) => setOverrideReason(e.target.value)} aria-describedby={describedBy} />
              </FormField>
              <Button
                type="button"
                variant="secondary"
                disabled={!overrideReason.trim()}
                loading={pending}
                loadingLabel="Overriding…"
                onClick={() =>
                  startTransition(async () => {
                    const result = await overrideMarginThresholdAction(tenantSlug, requestId, currentCalculation.id, currentCalculation.recordVersion, overrideReason.trim());
                    setError(result.error);
                  })
                }
              >
                Override threshold
              </Button>
            </div>
          ) : null}
        </div>
      ) : null}
    </div>
  );
}
