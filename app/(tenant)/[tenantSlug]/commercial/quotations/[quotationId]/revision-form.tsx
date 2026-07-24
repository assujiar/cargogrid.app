"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { createQuotationRevisionAction } from "./actions.ts";

/** Create-revision / restore-as-new-draft trigger (COM-152) -- both flows call the same app.create_quotation_revision RPC with sourceQuotationId set to whichever version is currently being viewed; the label communicates which case this is without the underlying mechanism differing. Mandatory reason (server-enforced, reason_required). */
export function RevisionForm({ tenantSlug, sourceQuotationId, isCurrent }: { tenantSlug: string; sourceQuotationId: string; isCurrent: boolean }) {
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">{isCurrent ? "Create new revision" : "Restore as new draft"}</h2>
      <p className="text-xs text-neutral-500">
        {isCurrent
          ? "Creates a new draft version from this one; this version becomes read-only history."
          : "Restores this historical version's data as a brand-new current draft; the version that was current becomes history instead."}
      </p>

      <input placeholder="Reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <Button
        type="button"
        variant="secondary"
        disabled={!reason.trim()}
        loading={pending}
        loadingLabel={isCurrent ? "Revising…" : "Restoring…"}
        onClick={() =>
          startTransition(async () => {
            const result = await createQuotationRevisionAction(tenantSlug, sourceQuotationId, reason.trim());
            if (result) setError(result.error);
          })
        }
      >
        {isCurrent ? "Create new revision" : "Restore as new draft"}
      </Button>
    </div>
  );
}
