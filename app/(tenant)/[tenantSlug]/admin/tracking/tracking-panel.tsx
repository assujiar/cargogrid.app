"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { TRACKING_SOURCE_TYPES, type ResolvedTenantTrackingSourcePolicy, type TrackingSourceType } from "../../../../../server/contracts/tracking-source-policy/tracking-source-policy.ts";
import type { TrackingPolicyFormState } from "./actions.ts";

const INITIAL_STATE: TrackingPolicyFormState = { error: null };

const SOURCE_LABELS: Record<TrackingSourceType, string> = {
  driver_mobile: "Driver mobile",
  direct_device: "Direct device (GPS gateway)",
  third_party_platform: "Third-party platform",
};

export function TrackingSourcePolicyPanel({
  sourcePolicy,
  action,
}: {
  sourcePolicy: ResolvedTenantTrackingSourcePolicy;
  action: (prevState: TrackingPolicyFormState, formData: FormData) => Promise<TrackingPolicyFormState>;
}) {
  const [state, formAction] = useActionState(action, INITIAL_STATE);

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Source arbitration policy</h2>
        <p className="text-xs text-neutral-500">
          {sourcePolicy.isExplicit ? "An explicit override is set for this organization." : "This organization is currently using the platform default."} Applies
          to every vehicle that has no per-vehicle override (ATW-223).
        </p>
      </div>
      <form action={formAction} className="flex flex-col gap-3">
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          {[0, 1, 2].map((rankIndex) => (
            <label key={rankIndex} className="flex flex-col gap-1 text-xs text-neutral-600">
              Priority {rankIndex + 1} (highest wins)
              <select name="defaultSourcePriority" defaultValue={sourcePolicy.defaultSourcePriority[rankIndex] ?? TRACKING_SOURCE_TYPES[rankIndex]} className="rounded border border-neutral-300 px-2 py-1 text-sm">
                {TRACKING_SOURCE_TYPES.map((sourceType) => (
                  <option key={sourceType} value={sourceType}>
                    {SOURCE_LABELS[sourceType]}
                  </option>
                ))}
              </select>
            </label>
          ))}
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Freshness threshold (seconds)
            <input type="number" name="freshnessThresholdSeconds" min={1} defaultValue={sourcePolicy.freshnessThresholdSeconds} className="rounded border border-neutral-300 px-2 py-1 text-sm" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Accuracy threshold (meters)
            <input type="number" name="accuracyThresholdMeters" min={1} defaultValue={sourcePolicy.accuracyThresholdMeters} className="rounded border border-neutral-300 px-2 py-1 text-sm" />
          </label>
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Switch hysteresis (seconds)
            <input type="number" name="switchHysteresisSeconds" min={0} defaultValue={sourcePolicy.switchHysteresisSeconds} className="rounded border border-neutral-300 px-2 py-1 text-sm" />
          </label>
        </div>
        {state.error ? <p className="text-xs text-danger-600">{state.error}</p> : null}
        <div>
          <Button type="submit">Save source policy</Button>
        </div>
      </form>
    </section>
  );
}
