"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { selectVendorRateAction } from "./actions.ts";
import type { RateVersion } from "../../../../../../server/contracts/rate/rate.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { RadioGroup } from "../../../../../../components/forms/radio.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

const MODE_OPTIONS = [
  { value: "catalog", label: "From catalog" },
  { value: "adhoc", label: "Ad-hoc quote" },
] as const;

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

  const describedBy = error ? "select-rate-error" : undefined;
  const invalid = Boolean(error);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Select a rate</h2>

      <RadioGroup
        legend="Rate source"
        name="mode"
        options={MODE_OPTIONS}
        value={mode}
        onChange={(value) => setMode(value as "catalog" | "adhoc")}
      />

      {mode === "catalog" ? (
        candidateRates.length === 0 ? (
          <p className="text-sm text-neutral-600">No approved, currently-effective rates for this tenant yet.</p>
        ) : (
          <FormField id="select-rate-version" label={<span className="sr-only">Approved rate</span>}>
            <Select id="select-rate-version" value={rateVersionId} onChange={(e) => setRateVersionId(e.target.value)} invalid={invalid} aria-describedby={describedBy}>
              {candidateRates.map((rate) => (
                <option key={rate.rateVersionId} value={rate.rateVersionId}>
                  {rate.vendorName} — {rate.originLane} → {rate.destinationLane} ({rate.serviceType}
                  {rate.costMasked ? "" : `, ${rate.baseAmount} ${rate.currency}`})
                </option>
              ))}
            </Select>
          </FormField>
        )
      ) : (
        <div className="flex gap-2">
          <div className="w-32">
            <FormField id="select-rate-adhoc-currency" label={<span className="sr-only">Currency</span>}>
              <Input id="select-rate-adhoc-currency" placeholder="Currency (e.g. IDR)" value={adhocCurrency} onChange={(e) => setAdhocCurrency(e.target.value.toUpperCase())} invalid={invalid} aria-describedby={describedBy} />
            </FormField>
          </div>
          <div className="w-40">
            <FormField id="select-rate-adhoc-amount" label={<span className="sr-only">Amount</span>}>
              <NumberInput id="select-rate-adhoc-amount" min={0} placeholder="Amount" value={adhocAmount} onChange={(e) => setAdhocAmount(e.target.value)} invalid={invalid} aria-describedby={describedBy} />
            </FormField>
          </div>
        </div>
      )}

      <FormField id="select-rate-override-reason" label={<span className="sr-only">Override reason</span>}>
        <Input
          id="select-rate-override-reason"
          placeholder={mode === "adhoc" ? "Override reason (required)" : "Override reason (required for a non-approved rate)"}
          value={overrideReason}
          onChange={(e) => setOverrideReason(e.target.value)}
          invalid={invalid}
          aria-describedby={describedBy}
        />
      </FormField>

      {error ? <ValidationMessage id="select-rate-error">{error}</ValidationMessage> : null}

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
