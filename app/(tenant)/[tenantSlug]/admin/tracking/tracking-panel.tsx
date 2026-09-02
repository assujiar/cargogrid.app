"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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
  // ISS-2026-242: the policy RPC returns one error for the whole save, never per-field ones.
  const describedBy = state.error ? "tracking-policy-error" : undefined;

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
            <FormField key={rankIndex} id={`tracking-priority-${rankIndex}`} label={`Priority ${rankIndex + 1} (highest wins)`}>
              <Select
                id={`tracking-priority-${rankIndex}`}
                name="defaultSourcePriority"
                defaultValue={sourcePolicy.defaultSourcePriority[rankIndex] ?? TRACKING_SOURCE_TYPES[rankIndex]}
                invalid={Boolean(state.error)}
                aria-describedby={describedBy}
              >
                {TRACKING_SOURCE_TYPES.map((sourceType) => (
                  <option key={sourceType} value={sourceType}>
                    {SOURCE_LABELS[sourceType]}
                  </option>
                ))}
              </Select>
            </FormField>
          ))}
        </div>
        <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <FormField id="tracking-freshness" label="Freshness threshold (seconds)">
            <NumberInput
              id="tracking-freshness"
              name="freshnessThresholdSeconds"
              min={1}
              defaultValue={sourcePolicy.freshnessThresholdSeconds}
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
          <FormField id="tracking-accuracy" label="Accuracy threshold (meters)">
            <NumberInput
              id="tracking-accuracy"
              name="accuracyThresholdMeters"
              min={1}
              defaultValue={sourcePolicy.accuracyThresholdMeters}
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
          <FormField id="tracking-hysteresis" label="Switch hysteresis (seconds)">
            <NumberInput
              id="tracking-hysteresis"
              name="switchHysteresisSeconds"
              min={0}
              defaultValue={sourcePolicy.switchHysteresisSeconds}
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
        </div>
        {state.error ? <ValidationMessage id="tracking-policy-error">{state.error}</ValidationMessage> : null}
        <div>
          <Button type="submit">Save source policy</Button>
        </div>
      </form>
    </section>
  );
}
