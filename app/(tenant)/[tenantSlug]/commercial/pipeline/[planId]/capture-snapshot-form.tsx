"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { captureForecastSnapshotAction } from "../actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Per-target inline snapshot capture (COM-146) -- computes the actual from canonical Lead/Prospect data and, optionally, records a reasoned manual override. */
export function CaptureSnapshotForm({ tenantSlug, planId, targetId }: { tenantSlug: string; planId: string; targetId: string }) {
  const [overrideValue, setOverrideValue] = useState("");
  const [overrideReason, setOverrideReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  // One instance renders per target row, so every id is already target-scoped -- the
  // error id follows the same rule so `aria-describedby` cannot cross rows.
  const errorId = `capture-snapshot-error-${targetId}`;
  const describedBy = error ? errorId : undefined;
  const invalid = Boolean(error);

  return (
    <div className="flex flex-wrap items-end gap-2">
      <FormField
        id={`override-${targetId}`}
        label={
          <>
            Override value <span className="font-normal text-neutral-500">(optional)</span>
          </>
        }
      >
        <div className="w-24">
          <NumberInput
            id={`override-${targetId}`}
            min={0}
            value={overrideValue}
            onChange={(event) => setOverrideValue(event.target.value)}
            invalid={invalid}
            aria-describedby={describedBy}
          />
        </div>
      </FormField>
      <FormField id={`override-reason-${targetId}`} label="Override reason">
        <div className="w-56">
          <Input
            id={`override-reason-${targetId}`}
            type="text"
            value={overrideReason}
            onChange={(event) => setOverrideReason(event.target.value)}
            invalid={invalid}
            aria-describedby={describedBy}
          />
        </div>
      </FormField>
      <Button
        type="button"
        variant="secondary"
        loading={pending}
        loadingLabel="Capturing…"
        disabled={overrideValue.trim() !== "" && !overrideReason.trim()}
        onClick={() =>
          startTransition(async () => {
            const trimmedOverride = overrideValue.trim();
            const result = await captureForecastSnapshotAction(
              tenantSlug,
              planId,
              targetId,
              trimmedOverride === "" ? null : Number(trimmedOverride),
              trimmedOverride === "" ? null : overrideReason.trim(),
            );
            setError(result.error);
          })
        }
      >
        Capture snapshot
      </Button>
      {error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{error}</ValidationMessage>
        </div>
      ) : null}
    </div>
  );
}
