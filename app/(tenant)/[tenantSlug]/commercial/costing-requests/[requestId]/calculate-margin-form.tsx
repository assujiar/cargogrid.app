"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { calculateMarginAction, overrideMarginThresholdAction } from "./actions.ts";
import type { MarginCalculation } from "../../../../../../server/contracts/margin/margin.ts";
import type { RateSelection } from "../../../../../../server/contracts/rate/rate.ts";

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

  const needsOverride = currentCalculation?.thresholdOutcome === "requires_approval" && !currentCalculation.isOverridden;

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Margin calculation</h2>

      {rateSelections.length === 0 ? (
        <p className="text-sm text-neutral-600">Select a rate above before calculating a margin.</p>
      ) : (
        <>
          <select value={rateSelectionId} onChange={(e) => setRateSelectionId(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
            {rateSelections.map((selection) => (
              <option key={selection.id} value={selection.id}>
                {selection.isAdhoc ? "Ad-hoc selection" : "Catalog selection"} ({selection.id.slice(0, 8)})
              </option>
            ))}
          </select>
          <div className="flex gap-2">
            <input type="number" min={0} placeholder="Sell amount" value={sellAmount} onChange={(e) => setSellAmount(e.target.value)} className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
            <input placeholder="Currency (e.g. IDR)" value={sellCurrency} onChange={(e) => setSellCurrency(e.target.value.toUpperCase())} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
            <input type="number" min={0} max={100} placeholder="Discount %" value={discountPct} onChange={(e) => setDiscountPct(e.target.value)} className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          </div>

          {error ? (
            <p role="alert" className="text-sm text-danger">
              {error}
            </p>
          ) : null}

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
              <input placeholder="Override reason" value={overrideReason} onChange={(e) => setOverrideReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
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
