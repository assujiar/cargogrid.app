"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { selectVendorRateAction } from "./actions.ts";
import type { RateVersion } from "../../../../../../server/contracts/rate/rate.ts";

/**
 * Select-rate trigger (COM-149) -- pick from the tenant's approved, currently-effective
 * rates, or record an ad-hoc quote with a mandatory override reason (a governed escape
 * hatch, not a silent bypass -- app.select_vendor_rate enforces the same rule server-side
 * regardless of what this form sends). Disclosed UI scope boundary: the candidate list
 * here is the tenant's own app.v_active_vendor_rates rows passed in by the parent page
 * (already lane-agnostic) -- a live, in-form lane/service search calling
 * app.search_vendor_rates is a richer iteration this bounded slice defers.
 */
export function SelectRateForm({ tenantSlug, requestId, candidateRates }: { tenantSlug: string; requestId: string; candidateRates: readonly RateVersion[] }) {
  const [mode, setMode] = useState<"catalog" | "adhoc">("catalog");
  const [rateVersionId, setRateVersionId] = useState(candidateRates[0]?.rateVersionId ?? "");
  const [adhocCurrency, setAdhocCurrency] = useState("");
  const [adhocAmount, setAdhocAmount] = useState("");
  const [overrideReason, setOverrideReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Select a rate</h2>

      <div className="flex gap-4 text-sm">
        <label className="flex items-center gap-1">
          <input type="radio" name="mode" checked={mode === "catalog"} onChange={() => setMode("catalog")} /> From catalog
        </label>
        <label className="flex items-center gap-1">
          <input type="radio" name="mode" checked={mode === "adhoc"} onChange={() => setMode("adhoc")} /> Ad-hoc quote
        </label>
      </div>

      {mode === "catalog" ? (
        candidateRates.length === 0 ? (
          <p className="text-sm text-neutral-600">No approved, currently-effective rates for this tenant yet.</p>
        ) : (
          <select value={rateVersionId} onChange={(e) => setRateVersionId(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
            {candidateRates.map((rate) => (
              <option key={rate.rateVersionId} value={rate.rateVersionId}>
                {rate.vendorName} — {rate.originLane} → {rate.destinationLane} ({rate.serviceType}
                {rate.costMasked ? "" : `, ${rate.baseAmount} ${rate.currency}`})
              </option>
            ))}
          </select>
        )
      ) : (
        <div className="flex gap-2">
          <input placeholder="Currency (e.g. IDR)" value={adhocCurrency} onChange={(e) => setAdhocCurrency(e.target.value.toUpperCase())} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
          <input type="number" min={0} placeholder="Amount" value={adhocAmount} onChange={(e) => setAdhocAmount(e.target.value)} className="w-40 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      )}

      <input
        placeholder={mode === "adhoc" ? "Override reason (required)" : "Override reason (required for a non-approved rate)"}
        value={overrideReason}
        onChange={(e) => setOverrideReason(e.target.value)}
        className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
      />

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <Button
        type="button"
        disabled={mode === "catalog" ? !rateVersionId : !adhocCurrency.trim() || !adhocAmount.trim() || !overrideReason.trim()}
        loading={pending}
        loadingLabel="Selecting…"
        onClick={() =>
          startTransition(async () => {
            const result = await selectVendorRateAction(
              tenantSlug,
              requestId,
              mode === "catalog" ? rateVersionId : null,
              mode === "adhoc",
              mode === "adhoc" ? adhocCurrency.trim() : null,
              mode === "adhoc" ? Number(adhocAmount) : null,
              overrideReason.trim() || null,
            );
            setError(result.error);
          })
        }
      >
        Select rate
      </Button>
    </div>
  );
}
