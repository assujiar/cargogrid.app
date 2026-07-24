"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { addQuotationLineAction } from "./actions.ts";
import type { QuotationLineType } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { MarginCalculation } from "../../../../../../server/contracts/margin/margin.ts";

const LINE_TYPES: readonly QuotationLineType[] = ["service", "surcharge", "fee", "discount"];

/** Line-add form (COM-151) -- selecting a sourcing margin calculation prefills the unit price from its net sell amount (when not cost/sell-masked for this viewer); a manual line (no calculation) is also supported. Editing a line's numbers is done by removing and re-adding it (migration's own disclosed boundary). */
export function AddLineForm({
  tenantSlug,
  quotationId,
  recordVersion,
  availableCalculations,
}: {
  tenantSlug: string;
  quotationId: string;
  recordVersion: number;
  availableCalculations: readonly MarginCalculation[];
}) {
  const [lineType, setLineType] = useState<QuotationLineType>("service");
  const [description, setDescription] = useState("");
  const [marginCalculationId, setMarginCalculationId] = useState("");
  const [quantity, setQuantity] = useState("1");
  const [unitPrice, setUnitPrice] = useState("");
  const [discountPct, setDiscountPct] = useState("0");
  const [taxPct, setTaxPct] = useState("0");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function applyCalculation(id: string) {
    setMarginCalculationId(id);
    const calc = availableCalculations.find((c) => c.id === id);
    if (calc?.netSellAmount !== null && calc?.netSellAmount !== undefined) {
      setUnitPrice(String(calc.netSellAmount));
    }
  }

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Add line</h2>

      {availableCalculations.length > 0 ? (
        <select value={marginCalculationId} onChange={(e) => applyCalculation(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="">No sourcing margin calculation (manual line)</option>
          {availableCalculations.map((calc) => (
            <option key={calc.id} value={calc.id}>
              {calc.marginPct === null ? "Restricted" : `${calc.marginPct}% margin`} ({calc.id.slice(0, 8)})
            </option>
          ))}
        </select>
      ) : (
        <p className="text-sm text-neutral-600">No calculated rates are available to source from yet -- this will be a manual line.</p>
      )}

      <select value={lineType} onChange={(e) => setLineType(e.target.value as QuotationLineType)} className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm">
        {LINE_TYPES.map((type) => (
          <option key={type} value={type}>
            {type}
          </option>
        ))}
      </select>

      <input placeholder="Description" value={description} onChange={(e) => setDescription(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />

      <div className="flex gap-2">
        <input type="number" min={0} step="0.001" placeholder="Quantity" value={quantity} onChange={(e) => setQuantity(e.target.value)} className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="number" min={0} placeholder="Unit price" value={unitPrice} onChange={(e) => setUnitPrice(e.target.value)} className="w-36 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="number" min={0} max={100} placeholder="Discount %" value={discountPct} onChange={(e) => setDiscountPct(e.target.value)} className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="number" min={0} max={100} placeholder="Tax %" value={taxPct} onChange={(e) => setTaxPct(e.target.value)} className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <Button
        type="button"
        disabled={!description.trim() || !unitPrice.trim()}
        loading={pending}
        loadingLabel="Adding…"
        onClick={() =>
          startTransition(async () => {
            const result = await addQuotationLineAction(
              tenantSlug,
              quotationId,
              recordVersion,
              lineType,
              description.trim(),
              marginCalculationId || null,
              Number(quantity) || 0,
              Number(unitPrice) || 0,
              Number(discountPct) || 0,
              Number(taxPct) || 0,
            );
            setError(result.error);
            if (!result.error) {
              setDescription("");
              setMarginCalculationId("");
              setUnitPrice("");
            }
          })
        }
      >
        Add line
      </Button>
    </div>
  );
}
