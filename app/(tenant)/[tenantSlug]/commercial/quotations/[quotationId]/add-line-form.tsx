"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { addQuotationLineAction } from "./actions.ts";
import type { QuotationLineType } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { MarginCalculation } from "../../../../../../server/contracts/margin/margin.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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

  const describedBy = error ? "add-line-error" : undefined;
  const invalid = Boolean(error);

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
        <FormField id="add-line-calculation" label={<span className="sr-only">Sourcing margin calculation</span>}>
          <Select id="add-line-calculation" value={marginCalculationId} onChange={(e) => applyCalculation(e.target.value)} invalid={invalid} aria-describedby={describedBy}>
            <option value="">No sourcing margin calculation (manual line)</option>
            {availableCalculations.map((calc) => (
              <option key={calc.id} value={calc.id}>
                {calc.marginPct === null ? "Restricted" : `${calc.marginPct}% margin`} ({calc.id.slice(0, 8)})
              </option>
            ))}
          </Select>
        </FormField>
      ) : (
        <p className="text-sm text-neutral-600">No calculated rates are available to source from yet -- this will be a manual line.</p>
      )}

      <div className="w-40">
        <FormField id="add-line-type" label={<span className="sr-only">Line type</span>}>
          <Select id="add-line-type" value={lineType} onChange={(e) => setLineType(e.target.value as QuotationLineType)} invalid={invalid} aria-describedby={describedBy}>
            {LINE_TYPES.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </Select>
        </FormField>
      </div>

      <FormField id="add-line-description" label={<span className="sr-only">Description</span>}>
        <Input id="add-line-description" placeholder="Description" value={description} onChange={(e) => setDescription(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
      </FormField>

      <div className="flex gap-2">
        <div className="w-28">
          <FormField id="add-line-quantity" label={<span className="sr-only">Quantity</span>}>
            <NumberInput id="add-line-quantity" min={0} step="0.001" placeholder="Quantity" value={quantity} onChange={(e) => setQuantity(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-36">
          <FormField id="add-line-unit-price" label={<span className="sr-only">Unit price</span>}>
            <Input type="number" inputMode="decimal" id="add-line-unit-price" min={0} placeholder="Unit price" value={unitPrice} onChange={(e) => setUnitPrice(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-28">
          <FormField id="add-line-discount-pct" label={<span className="sr-only">Discount %</span>}>
            <NumberInput id="add-line-discount-pct" min={0} max={100} placeholder="Discount %" value={discountPct} onChange={(e) => setDiscountPct(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-28">
          <FormField id="add-line-tax-pct" label={<span className="sr-only">Tax %</span>}>
            <NumberInput id="add-line-tax-pct" min={0} max={100} placeholder="Tax %" value={taxPct} onChange={(e) => setTaxPct(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      {error ? <ValidationMessage id="add-line-error">{error}</ValidationMessage> : null}

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
