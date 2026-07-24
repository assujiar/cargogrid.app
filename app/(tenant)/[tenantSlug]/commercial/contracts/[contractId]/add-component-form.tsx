"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { addPriceComponentAction } from "./actions.ts";

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

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Add price component</h2>

      <input placeholder="Service type (e.g. ocean_freight)" value={serviceType} onChange={(e) => setServiceType(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />

      <div className="flex gap-2">
        <input placeholder="Mode (optional)" value={mode} onChange={(e) => setMode(e.target.value)} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input placeholder="Origin lane (optional)" value={originLane} onChange={(e) => setOriginLane(e.target.value)} className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input placeholder="Destination lane (optional)" value={destinationLane} onChange={(e) => setDestinationLane(e.target.value)} className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input placeholder="Equipment (optional)" value={equipmentType} onChange={(e) => setEquipmentType(e.target.value)} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      <div className="flex gap-2">
        <input placeholder="Currency" value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} maxLength={3} className="w-24 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="number" min={0} placeholder="Base amount" value={baseAmount} onChange={(e) => setBaseAmount(e.target.value)} className="w-36 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="number" min={0} placeholder="Minimum (optional)" value={minimumAmount} onChange={(e) => setMinimumAmount(e.target.value)} className="w-36 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="number" min={0} max={100} placeholder="Discount %" value={discountPct} onChange={(e) => setDiscountPct(e.target.value)} className="w-28 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

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
