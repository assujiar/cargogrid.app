"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { VendorRateTier } from "../../../../../../server/contracts/procurement-rate/procurement-rate.ts";
import type { RateVersionApprovalStatus } from "../../../../../../server/contracts/rate/rate.ts";
import type { ProcurementRateActionState, CalculatePreviewState } from "../actions.ts";

const TIER_INITIAL_STATE: ProcurementRateActionState = { error: null };
const CALC_INITIAL_STATE: CalculatePreviewState = { error: null, result: null };

/**
 * Structured tier editor + calculation preview (PRC-255, Prompt 255 §15). Add/remove
 * only while the rate is pending_approval (mirrors the DB's own "child rows only
 * while parent is editable" convention); the calculation preview works for any
 * status (a published rate's own tiers are still previewable read-only).
 */
export function RateTierPanel({
  rateStatus,
  tiers,
  addTierAction,
  removeTierAction,
  calculateAction,
}: {
  rateStatus: RateVersionApprovalStatus;
  tiers: readonly VendorRateTier[];
  addTierAction: (prevState: ProcurementRateActionState, formData: FormData) => Promise<ProcurementRateActionState>;
  removeTierAction: (prevState: ProcurementRateActionState, formData: FormData) => Promise<ProcurementRateActionState>;
  calculateAction: (prevState: CalculatePreviewState, formData: FormData) => Promise<CalculatePreviewState>;
}) {
  const [addState, addFormAction, addPending] = useActionState(addTierAction, TIER_INITIAL_STATE);
  const [removeState, removeFormAction] = useActionState(removeTierAction, TIER_INITIAL_STATE);
  const [calcState, calcFormAction, calcPending] = useActionState(calculateAction, CALC_INITIAL_STATE);

  const editable = rateStatus === "pending_approval";

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Weight/volume tiers</h2>
        <p className="text-xs text-neutral-500">
          Ordered, [min,max)-half-open, validated for contiguity/non-overlap at approval time (never at every edit). Zero tiers keeps the flat base amount as the only price.
        </p>

        {tiers.length === 0 ? (
          <EmptyState title="No tiers yet" description="This rate uses its flat base amount for every shipment. Add a tier below to introduce weight/volume breaks." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Order</th>
                  <th className="px-3 py-2">Weight</th>
                  <th className="px-3 py-2">Volume</th>
                  <th className="px-3 py-2">Amount</th>
                  <th className="px-3 py-2">Minimum</th>
                  {editable ? <th className="px-3 py-2" /> : null}
                </tr>
              </thead>
              <tbody>
                {tiers.map((tier) => (
                  <tr key={tier.id} className="border-t border-neutral-200">
                    <td className="px-3 py-2">{tier.tierOrder}</td>
                    <td className="px-3 py-2 text-neutral-700">
                      [{tier.weightMin}, {tier.weightMax ?? "∞"})
                    </td>
                    <td className="px-3 py-2 text-neutral-700">
                      [{tier.volumeMin}, {tier.volumeMax ?? "∞"})
                    </td>
                    <td className="px-3 py-2 text-neutral-700">{tier.costMasked ? <span className="italic text-neutral-400">masked</span> : tier.amount}</td>
                    <td className="px-3 py-2 text-neutral-700">{tier.costMasked ? <span className="italic text-neutral-400">masked</span> : (tier.minimumCharge ?? "—")}</td>
                    {editable ? (
                      <td className="px-3 py-2">
                        <form action={removeFormAction}>
                          <input type="hidden" name="tierId" value={tier.id} />
                          <input type="hidden" name="expectedVersion" value={tier.recordVersion} />
                          <Button type="submit" variant="destructive">
                            Remove
                          </Button>
                        </form>
                      </td>
                    ) : null}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {removeState.error ? (
          <p role="alert" className="text-sm text-danger">
            {removeState.error}
          </p>
        ) : null}

        {editable ? (
          <form action={addFormAction} className="grid grid-cols-3 gap-3 border-t border-neutral-200 pt-3" noValidate>
            <div className="flex flex-col gap-1">
              <label htmlFor="tierOrder" className="text-sm font-medium text-neutral-700">Tier order</label>
              <Input id="tierOrder" name="tierOrder" type="number" min={1} required />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="weightMin" className="text-sm font-medium text-neutral-700">Weight min</label>
              <Input id="weightMin" name="weightMin" type="number" min={0} />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="weightMax" className="text-sm font-medium text-neutral-700">Weight max (blank = unbounded)</label>
              <Input id="weightMax" name="weightMax" type="number" min={0} />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="volumeMin" className="text-sm font-medium text-neutral-700">Volume min</label>
              <Input id="volumeMin" name="volumeMin" type="number" min={0} />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="volumeMax" className="text-sm font-medium text-neutral-700">Volume max (blank = unbounded)</label>
              <Input id="volumeMax" name="volumeMax" type="number" min={0} />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="amount" className="text-sm font-medium text-neutral-700">Amount</label>
              <Input id="amount" name="amount" type="number" min={0} required />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="minimumCharge" className="text-sm font-medium text-neutral-700">Minimum charge (optional)</label>
              <Input id="minimumCharge" name="minimumCharge" type="number" min={0} />
            </div>
            {addState.error ? (
              <p role="alert" className="col-span-3 text-sm text-danger">
                {addState.error}
              </p>
            ) : null}
            <Button type="submit" loading={addPending} loadingLabel="Adding…" className="col-span-3">
              Add tier
            </Button>
          </form>
        ) : (
          <p className="text-xs text-neutral-500">Tiers may only be added or removed while this rate is pending approval.</p>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Calculate preview</h2>
        <p className="text-xs text-neutral-500">Read-only, no side effect (RPD-040). Requires PRC:View cost.</p>
        <form action={calcFormAction} className="grid grid-cols-3 gap-3" noValidate>
          <div className="flex flex-col gap-1">
            <label htmlFor="weight" className="text-sm font-medium text-neutral-700">Weight</label>
            <Input id="weight" name="weight" type="number" min={0} />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="volume" className="text-sm font-medium text-neutral-700">Volume</label>
            <Input id="volume" name="volume" type="number" min={0} />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="quantity" className="text-sm font-medium text-neutral-700">Quantity</label>
            <Input id="quantity" name="quantity" type="number" min={0} />
          </div>
          {calcState.error ? (
            <p role="alert" className="col-span-3 text-sm text-danger">
              {calcState.error}
            </p>
          ) : null}
          {calcState.result ? (
            <p className="col-span-3 text-sm text-neutral-900">
              Computed amount: <strong>{calcState.result.currency} {calcState.result.computedAmount}</strong>
              {calcState.result.matchedTierId ? " (tier matched)" : " (flat base amount)"}
              {calcState.result.minimumAmountApplied ? " — minimum applied" : ""}
            </p>
          ) : null}
          <Button type="submit" loading={calcPending} loadingLabel="Calculating…" className="col-span-3">
            Calculate
          </Button>
        </form>
      </section>
    </div>
  );
}
