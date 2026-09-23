"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { checkEffectiveCustomerPriceAction } from "./actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { EffectiveCustomerPrice } from "../../../../../../server/contracts/contract/contract.ts";

/** CG-AUDIT-2026-09-02 E1: previews what app.get_effective_customer_price would actually resolve for a lane/service, against this contract's own published price components -- mirrors AddComponentForm's own "local state, submit via startTransition" pattern, the same 5 dimension fields already shown in the price-components table above. Read-only; never mutates anything. */
export function CheckEffectivePriceForm({ tenantSlug, accountId }: { tenantSlug: string; accountId: string }) {
  const [serviceType, setServiceType] = useState("");
  const [mode, setMode] = useState("");
  const [originLane, setOriginLane] = useState("");
  const [destinationLane, setDestinationLane] = useState("");
  const [equipmentType, setEquipmentType] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [result, setResult] = useState<EffectiveCustomerPrice | null>(null);
  const [pending, startTransition] = useTransition();

  const describedBy = error ? "check-effective-price-error" : undefined;
  const invalid = Boolean(error);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Check effective price</h2>
      <p className="text-xs text-neutral-600">Preview what a customer would actually be charged for a lane/service, resolved against this account&apos;s own published contract.</p>

      <FormField id="check-effective-price-service-type" label={<span className="sr-only">Service type</span>}>
        <Input id="check-effective-price-service-type" placeholder="Service type (e.g. ocean_freight)" value={serviceType} onChange={(e) => setServiceType(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
      </FormField>

      <div className="flex gap-2">
        <div className="w-32">
          <FormField id="check-effective-price-mode" label={<span className="sr-only">Mode</span>}>
            <Input id="check-effective-price-mode" placeholder="Mode (optional)" value={mode} onChange={(e) => setMode(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-40">
          <FormField id="check-effective-price-origin-lane" label={<span className="sr-only">Origin lane</span>}>
            <Input id="check-effective-price-origin-lane" placeholder="Origin lane (optional)" value={originLane} onChange={(e) => setOriginLane(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-40">
          <FormField id="check-effective-price-destination-lane" label={<span className="sr-only">Destination lane</span>}>
            <Input id="check-effective-price-destination-lane" placeholder="Destination lane (optional)" value={destinationLane} onChange={(e) => setDestinationLane(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-32">
          <FormField id="check-effective-price-equipment-type" label={<span className="sr-only">Equipment</span>}>
            <Input id="check-effective-price-equipment-type" placeholder="Equipment (optional)" value={equipmentType} onChange={(e) => setEquipmentType(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      {error ? <ValidationMessage id="check-effective-price-error">{error}</ValidationMessage> : null}

      {result ? (
        <dl className="grid grid-cols-2 gap-x-6 gap-y-1 rounded-md bg-neutral-50 p-3 text-sm">
          <dt className="font-medium text-neutral-600">Resolved price</dt>
          <dd className="text-neutral-900">{result.priceMasked ? "Restricted (no COM:View selling price)" : result.baseAmount !== null ? `${result.baseAmount} ${result.currency ?? ""}` : "—"}</dd>
          <dt className="font-medium text-neutral-600">Discount</dt>
          <dd className="text-neutral-900">{result.priceMasked ? "Restricted" : (result.discountPct ?? 0)}%</dd>
          <dt className="font-medium text-neutral-600">Effective from</dt>
          <dd className="text-neutral-900">{new Date(result.effectiveFrom).toLocaleDateString()}</dd>
          <dt className="font-medium text-neutral-600">Effective to</dt>
          <dd className="text-neutral-900">{result.effectiveTo ? new Date(result.effectiveTo).toLocaleDateString() : "Open-ended"}</dd>
        </dl>
      ) : null}

      <Button
        type="button"
        disabled={!serviceType.trim()}
        loading={pending}
        loadingLabel="Checking…"
        onClick={() =>
          startTransition(async () => {
            const state = await checkEffectiveCustomerPriceAction(
              tenantSlug,
              accountId,
              serviceType.trim(),
              mode.trim() || null,
              originLane.trim() || null,
              destinationLane.trim() || null,
              equipmentType.trim() || null,
            );
            setError(state.error);
            setResult(state.result);
          })
        }
      >
        Check price
      </Button>
    </div>
  );
}
