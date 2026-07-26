"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { holdCreditProfileAction, releaseCreditProfileAction } from "./credit-actions.ts";

/** Hold/release (COM-157) -- both COM:Approve + reauth-freshness gated (see credit-approval-decision-form.tsx's own header for the disclosed reauth boundary). */
export function HoldReleaseForm({ tenantSlug, accountId, profileId, expectedVersion, status }: { tenantSlug: string; accountId: string; profileId: string; expectedVersion: number; status: "active" | "held" }) {
  const [reason, setReason] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function submit() {
    startTransition(async () => {
      const result =
        status === "active"
          ? await holdCreditProfileAction(tenantSlug, accountId, profileId, expectedVersion, reason.trim(), new Date().toISOString())
          : await releaseCreditProfileAction(tenantSlug, accountId, profileId, expectedVersion, new Date().toISOString());
      setError(result.error);
    });
  }

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      {status === "active" ? (
        <input placeholder="Hold reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      ) : null}
      <label className="flex items-center gap-2 text-xs text-neutral-600">
        <input type="checkbox" checked={reauthConfirmed} onChange={(e) => setReauthConfirmed(e.target.checked)} />
        I have recently re-authenticated (required for this action)
      </label>
      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}
      <Button type="button" variant={status === "active" ? "destructive" : "primary"} disabled={!reauthConfirmed || (status === "active" && !reason.trim())} loading={pending} loadingLabel={status === "active" ? "Holding…" : "Releasing…"} onClick={submit} className="w-fit">
        {status === "active" ? "Hold" : "Release"}
      </Button>
    </div>
  );
}
