"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { submitQuotationAction, cloneQuotationAction } from "./actions.ts";
import type { QuotationReadiness } from "../../../../../../server/contracts/quotation/quotation.ts";

/** Readiness display + submit/clone triggers (COM-151). Submit is blocked client-side purely as a UX nicety when readiness.ready is false -- the real, authoritative gate is app.submit_quotation's own server-side readiness check (Prompt 151 §25). */
export function SubmitAndCloneActions({
  tenantSlug,
  quotationId,
  recordVersion,
  status,
  readiness,
}: {
  tenantSlug: string;
  quotationId: string;
  recordVersion: number;
  status: string;
  readiness: QuotationReadiness;
}) {
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Submission readiness</h2>
      {readiness.ready ? (
        <p className="text-sm text-neutral-600">Ready to submit.</p>
      ) : (
        <p className="text-sm text-neutral-600">Not ready — blocking: {readiness.blockingReasons.join(", ")}.</p>
      )}

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <div className="flex gap-2">
        <Button
          type="button"
          disabled={status !== "draft" || !readiness.ready}
          loading={pending}
          loadingLabel="Submitting…"
          onClick={() =>
            startTransition(async () => {
              const result = await submitQuotationAction(tenantSlug, quotationId, recordVersion);
              setError(result.error);
            })
          }
        >
          Submit quotation
        </Button>
        <Button
          type="button"
          variant="secondary"
          loading={pending}
          loadingLabel="Cloning…"
          onClick={() =>
            startTransition(async () => {
              const result = await cloneQuotationAction(tenantSlug, quotationId);
              if (result) setError(result.error);
            })
          }
        >
          Clone as new draft
        </Button>
      </div>
    </div>
  );
}
