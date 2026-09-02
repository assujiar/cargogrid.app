"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { holdCreditProfileAction, releaseCreditProfileAction } from "./credit-actions.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Checkbox } from "../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

/** Hold/release (COM-157) -- both COM:Approve + reauth-freshness gated (see credit-approval-decision-form.tsx's own header for the disclosed reauth boundary). */
export function HoldReleaseForm({ tenantSlug, accountId, profileId, expectedVersion, status }: { tenantSlug: string; accountId: string; profileId: string; expectedVersion: number; status: "active" | "held" }) {
  const [reason, setReason] = useState("");
  const [reauthConfirmed, setReauthConfirmed] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const describedBy = error ? "hold-release-error" : undefined;

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
        <FormField id="hold-reason" label={<span className="sr-only">Hold reason (required)</span>}>
          <Input id="hold-reason" placeholder="Hold reason (required)" value={reason} onChange={(e) => setReason(e.target.value)} invalid={Boolean(error)} aria-describedby={describedBy} />
        </FormField>
      ) : null}
      <Checkbox
        checked={reauthConfirmed}
        onChange={(e) => setReauthConfirmed(e.target.checked)}
        label="I have recently re-authenticated (required for this action)"
        aria-describedby={describedBy}
      />
      {error ? <ValidationMessage id="hold-release-error">{error}</ValidationMessage> : null}
      <Button type="button" variant={status === "active" ? "destructive" : "primary"} disabled={!reauthConfirmed || (status === "active" && !reason.trim())} loading={pending} loadingLabel={status === "active" ? "Holding…" : "Releasing…"} onClick={submit} className="w-fit">
        {status === "active" ? "Hold" : "Release"}
      </Button>
    </div>
  );
}
