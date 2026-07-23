"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { disqualifyProspectAction, archiveProspectAction } from "./actions.ts";

/** Disqualify/archive action panel (COM-144, CG-S7-COM-003) -- mirrors COM-143's own `lead-actions-panel.tsx` pattern exactly. */
export function ProspectActionsPanel({
  tenantSlug,
  prospectId,
  recordVersion,
  status,
}: {
  tenantSlug: string;
  prospectId: string;
  recordVersion: number;
  status: string;
}) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const canAct = status === "active";

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <div className="flex flex-col gap-1">
        <label htmlFor="disqualify-reason" className="text-sm font-medium text-neutral-700">
          Disqualify reason
        </label>
        <input
          id="disqualify-reason"
          type="text"
          value={reason}
          onChange={(event) => setReason(event.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <Button
        type="button"
        variant="destructive"
        disabled={!canAct || !reason.trim()}
        loading={pending}
        loadingLabel="Disqualifying…"
        onClick={() =>
          startTransition(async () => {
            const result = await disqualifyProspectAction(tenantSlug, prospectId, recordVersion, reason);
            setError(result.error);
          })
        }
      >
        Disqualify
      </Button>

      <Button
        type="button"
        variant="secondary"
        disabled={!canAct}
        loading={pending}
        loadingLabel="Archiving…"
        onClick={() =>
          startTransition(async () => {
            const result = await archiveProspectAction(tenantSlug, prospectId, recordVersion);
            setError(result.error);
          })
        }
      >
        Archive
      </Button>
    </div>
  );
}
