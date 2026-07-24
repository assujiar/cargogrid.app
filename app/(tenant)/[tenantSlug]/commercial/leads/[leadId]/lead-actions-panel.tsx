"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { qualifyLeadAction, disqualifyLeadAction, convertLeadToProspectAction } from "../actions.ts";

/**
 * Qualify/disqualify/convert action panel (COM-143/`144`, CG-S7-COM-002/`003`) -- a
 * Client Component so the disqualify reason input, the convert legal-name input, and any
 * returned error can render without a full page navigation. Calls the bound Server
 * Actions directly (no `useActionState`/form needed -- each takes explicit args, not a
 * `FormData`) and relies on each action's own `revalidatePath`/`redirect` once it returns.
 */
export function LeadActionsPanel({
  tenantSlug,
  leadId,
  recordVersion,
  status,
  companyName,
}: {
  tenantSlug: string;
  leadId: string;
  recordVersion: number;
  status: string;
  companyName: string | null;
}) {
  const [reason, setReason] = useState("");
  const [legalName, setLegalName] = useState(companyName ?? "");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const canQualify = status === "new" || status === "contacted";
  const canDisqualify = status === "new" || status === "contacted" || status === "qualified";
  const canConvert = status === "qualified";

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <Button
        type="button"
        disabled={!canQualify}
        loading={pending}
        loadingLabel="Qualifying…"
        onClick={() =>
          startTransition(async () => {
            const result = await qualifyLeadAction(tenantSlug, leadId, recordVersion);
            setError(result.error);
          })
        }
      >
        Qualify
      </Button>

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
        disabled={!canDisqualify || !reason.trim()}
        loading={pending}
        loadingLabel="Disqualifying…"
        onClick={() =>
          startTransition(async () => {
            const result = await disqualifyLeadAction(tenantSlug, leadId, recordVersion, reason);
            setError(result.error);
          })
        }
      >
        Disqualify
      </Button>

      <hr className="border-neutral-200" />

      <div className="flex flex-col gap-1">
        <label htmlFor="convert-legal-name" className="text-sm font-medium text-neutral-700">
          Prospect legal name
        </label>
        <input
          id="convert-legal-name"
          type="text"
          value={legalName}
          onChange={(event) => setLegalName(event.target.value)}
          className="rounded-md border border-neutral-300 px-3 py-2 text-sm"
        />
      </div>
      <Button
        type="button"
        disabled={!canConvert || !legalName.trim()}
        loading={pending}
        loadingLabel="Converting…"
        onClick={() =>
          startTransition(async () => {
            const result = await convertLeadToProspectAction(tenantSlug, leadId, legalName);
            setError(result.error);
          })
        }
      >
        Convert to prospect
      </Button>
    </div>
  );
}
