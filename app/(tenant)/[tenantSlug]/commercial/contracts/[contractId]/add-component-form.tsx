"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { addPriceComponentAction } from "./actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Add-price-component form (COM-156) -- mirrors AddLineForm's (COM-151) own "local state, submit via startTransition" pattern. Only rendered while the owning contract is status=draft (the server-side gate the RPC itself also enforces). */
export function AddComponentForm({ tenantSlug, contractId }: { tenantSlug: string; contractId: string }) {
  const [serviceType, setServiceType] = useState("");
  const [mode, setMode] = useState("");
  const [originLane, setOriginLane] = useState("");
  const [destinationLane, setDestinationLane] = useState("");
  const [equipmentType, setEquipmentType] = useState("");
  const [currency, setCurrency] = useState("IDR");
  const [baseAmount, setBaseAmount] = useState("");
  const [minimumAmount, setMinimumAmount] = useState("");
  const [discountPct, setDiscountPct] = useState("0");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const describedBy = error ? "add-component-error" : undefined;
  const invalid = Boolean(error);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Add price component</h2>

      <FormField id="add-component-service-type" label={<span className="sr-only">Service type</span>}>
        <Input id="add-component-service-type" placeholder="Service type (e.g. ocean_freight)" value={serviceType} onChange={(e) => setServiceType(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
      </FormField>

      <div className="flex gap-2">
        <div className="w-32">
          <FormField id="add-component-mode" label={<span className="sr-only">Mode</span>}>
            <Input id="add-component-mode" placeholder="Mode (optional)" value={mode} onChange={(e) => setMode(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-40">
          <FormField id="add-component-origin-lane" label={<span className="sr-only">Origin lane</span>}>
            <Input id="add-component-origin-lane" placeholder="Origin lane (optional)" value={originLane} onChange={(e) => setOriginLane(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-40">
          <FormField id="add-component-destination-lane" label={<span className="sr-only">Destination lane</span>}>
            <Input id="add-component-destination-lane" placeholder="Destination lane (optional)" value={destinationLane} onChange={(e) => setDestinationLane(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-32">
          <FormField id="add-component-equipment-type" label={<span className="sr-only">Equipment</span>}>
            <Input id="add-component-equipment-type" placeholder="Equipment (optional)" value={equipmentType} onChange={(e) => setEquipmentType(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      <div className="flex gap-2">
        <div className="w-24">
          <FormField id="add-component-currency" label={<span className="sr-only">Currency</span>}>
            <Input id="add-component-currency" placeholder="Currency" value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} maxLength={3} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-36">
          <FormField id="add-component-base-amount" label={<span className="sr-only">Base amount</span>}>
            <NumberInput id="add-component-base-amount" min={0} placeholder="Base amount" value={baseAmount} onChange={(e) => setBaseAmount(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-36">
          <FormField id="add-component-minimum-amount" label={<span className="sr-only">Minimum amount</span>}>
            <NumberInput id="add-component-minimum-amount" min={0} placeholder="Minimum (optional)" value={minimumAmount} onChange={(e) => setMinimumAmount(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="w-28">
          <FormField id="add-component-discount-pct" label={<span className="sr-only">Discount %</span>}>
            <NumberInput id="add-component-discount-pct" min={0} max={100} placeholder="Discount %" value={discountPct} onChange={(e) => setDiscountPct(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      {error ? <ValidationMessage id="add-component-error">{error}</ValidationMessage> : null}

      <Button
        type="button"
        disabled={!serviceType.trim() || !currency.trim() || !baseAmount.trim()}
        loading={pending}
        loadingLabel="Adding…"
        onClick={() =>
          startTransition(async () => {
            const result = await addPriceComponentAction(
              tenantSlug,
              contractId,
              serviceType.trim(),
              mode.trim() || null,
              originLane.trim() || null,
              destinationLane.trim() || null,
              equipmentType.trim() || null,
              currency.trim(),
              Number(baseAmount) || 0,
              minimumAmount.trim() ? Number(minimumAmount) : null,
              Number(discountPct) || 0,
            );
            setError(result.error);
            if (!result.error) {
              setServiceType("");
              setBaseAmount("");
              setMinimumAmount("");
              setDiscountPct("0");
            }
          })
        }
      >
        Add component
      </Button>
    </div>
  );
}
