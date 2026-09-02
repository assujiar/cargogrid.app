"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { disqualifyProspectAction, archiveProspectAction } from "./actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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

  // Disqualify and archive share this one `error` slot, so the reason field points at the
  // shared message rather than claiming `aria-invalid` for an error archive may have set
  // (ISS-2026-242's own documented multi-action case).
  const describedBy = error ? "prospect-actions-error" : undefined;

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? <ValidationMessage id="prospect-actions-error">{error}</ValidationMessage> : null}

      <FormField id="disqualify-reason" label="Disqualify reason">
        <Input id="disqualify-reason" type="text" value={reason} onChange={(event) => setReason(event.target.value)} aria-describedby={describedBy} />
      </FormField>
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
