"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { captureForecastSnapshotAction } from "../actions.ts";

/** Per-target inline snapshot capture (COM-146) -- computes the actual from canonical Lead/Prospect data and, optionally, records a reasoned manual override. */
export function CaptureSnapshotForm({ tenantSlug, planId, targetId }: { tenantSlug: string; planId: string; targetId: string }) {
  const [overrideValue, setOverrideValue] = useState("");
  const [overrideReason, setOverrideReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-wrap items-end gap-2">
      <div className="flex flex-col gap-1">
        <label htmlFor={`override-${targetId}`} className="text-xs font-medium text-neutral-700">
          Override value <span className="font-normal text-neutral-500">(optional)</span>
        </label>
        <input
          id={`override-${targetId}`}
          type="number"
          min={0}
          value={overrideValue}
          onChange={(event) => setOverrideValue(event.target.value)}
          className="w-24 rounded-md border border-neutral-300 px-2 py-1 text-sm"
        />
      </div>
      <div className="flex flex-col gap-1">
        <label htmlFor={`override-reason-${targetId}`} className="text-xs font-medium text-neutral-700">
          Override reason
        </label>
        <input
          id={`override-reason-${targetId}`}
          type="text"
          value={overrideReason}
          onChange={(event) => setOverrideReason(event.target.value)}
          className="w-56 rounded-md border border-neutral-300 px-2 py-1 text-sm"
        />
      </div>
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
        <p role="alert" className="w-full text-xs text-danger">
          {error}
        </p>
      ) : null}
    </div>
  );
}
