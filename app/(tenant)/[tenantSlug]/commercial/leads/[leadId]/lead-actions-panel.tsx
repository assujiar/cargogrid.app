"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { qualifyLeadAction, disqualifyLeadAction, convertLeadToProspectAction } from "../actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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

  // Qualify, disqualify and convert all write into this one `error` slot, so neither
  // field can honestly claim `aria-invalid`; both instead point at the shared message
  // (ISS-2026-242's own documented multi-action case).
  const describedBy = error ? "lead-actions-error" : undefined;

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? <ValidationMessage id="lead-actions-error">{error}</ValidationMessage> : null}

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

      <FormField id="disqualify-reason" label="Disqualify reason">
        <Input id="disqualify-reason" type="text" value={reason} onChange={(event) => setReason(event.target.value)} aria-describedby={describedBy} />
      </FormField>
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

      <FormField id="convert-legal-name" label="Prospect legal name">
        <Input id="convert-legal-name" type="text" value={legalName} onChange={(event) => setLegalName(event.target.value)} aria-describedby={describedBy} />
      </FormField>
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
