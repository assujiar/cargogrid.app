import type { Quotation } from "../../../../../../server/contracts/quotation/quotation.ts";
import type { JobOrderHandoff } from "../../../../../../server/contracts/job-order-lineage/job-order-lineage.ts";
import type { AccountConversionRecord } from "../../../../../../server/queries/account.ts";
import { PrepareJobOrderHandoffForm } from "./prepare-job-order-handoff-form.tsx";
import { prepareJobOrderHandoffAction } from "./actions.ts";

/**
 * Full Lineage into Job Order panel (COM-160, CG-S7-COM-019) -- a conversion preview/
 * status surface only, never a Job Order editor (Prompt 160 §15's own explicit "no Job
 * Order editor here"). Renders only once the customer has accepted and the quotation
 * has been converted to an account (COM-155) -- both are hard preconditions
 * `app.prepare_job_order_handoff` itself enforces, restated here only for UI
 * affordance. Once a handoff exists, shows its status/schema version/masked-aware
 * pricing summary and an inert "source references" list -- every field traces to a
 * canonical Commercial record, never a duplicate Job Order form.
 */
export function JobOrderHandoffPanel({
  tenantSlug,
  quotation,
  existingConversion,
  existingHandoff,
}: {
  tenantSlug: string;
  quotation: Quotation;
  existingConversion: AccountConversionRecord | null;
  existingHandoff: JobOrderHandoff | null;
}) {
  if (quotation.customerDecision !== "accepted" || !existingConversion) {
    return null;
  }

  const boundAction = prepareJobOrderHandoffAction.bind(null, tenantSlug, quotation.id);

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Job Order handoff</h2>
      <p className="text-xs text-neutral-500">
        Commercial produces one versioned snapshot for Operations to consume -- no Job Order is created here.
      </p>

      {existingHandoff ? (
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Status</dt>
          <dd className="text-neutral-900">{existingHandoff.status}</dd>
          <dt className="text-neutral-600">Schema version</dt>
          <dd className="text-neutral-900">{existingHandoff.schemaVersion}</dd>
          <dt className="text-neutral-600">Prepared</dt>
          <dd className="text-neutral-900">{existingHandoff.createdAt}</dd>
          <dt className="text-neutral-600">Total amount</dt>
          <dd className="text-neutral-900">
            {existingHandoff.payloadMasked || !existingHandoff.payload
              ? "Masked"
              : `${existingHandoff.payload.pricing.currency} ${existingHandoff.payload.pricing.totalAmount.toLocaleString("en-US")}`}
          </dd>
          <dt className="text-neutral-600">Downstream reference</dt>
          <dd className="text-neutral-900">{existingHandoff.downstreamReference ?? "Not yet delivered"}</dd>
        </dl>
      ) : (
        <PrepareJobOrderHandoffForm action={boundAction} />
      )}
    </div>
  );
}
