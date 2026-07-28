"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { TransactionLineageManifest, TransactionLineageRelationType } from "../../../../../../server/contracts/transaction-lineage/transaction-lineage.ts";
import type { JobOrderFormState } from "./actions.ts";

const INITIAL_STATE: JobOrderFormState = { error: null };

const RELATION_LABELS: Record<TransactionLineageRelationType, string> = {
  quote_to_job: "Quote handoff → Job Order",
  job_to_shipment: "Job Order → Shipment Order",
  shipment_to_epod: "Shipment Order → ePOD capture",
  shipment_to_cost: "Shipment Order → Actual cost",
  job_to_profitability: "Job Order → Profitability snapshot",
  job_to_billing_readiness: "Job Order → Billing readiness",
};

/** OPS-184: the full quote-to-billing lineage manifest -- shipments with their ePOD/actual-cost/milestone children, the profitability and billing-readiness nodes, and the raw captured edges. A bounded corrective-override form lets an OPS:Override holder add a reasoned additional mapping (e.g. a consolidation correction) without ever deleting the original evidence. */
export function TransactionLineagePanel({
  manifest,
  overrideAction,
}: {
  readonly manifest: TransactionLineageManifest | null;
  readonly overrideAction: (prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState>;
}) {
  const [overrideState, overrideFormAction, overridePending] = useActionState(overrideAction, INITIAL_STATE);

  if (!manifest) {
    return <p className="text-sm text-neutral-500">Lineage is not available for this Job Order.</p>;
  }

  return (
    <div className="flex flex-col gap-3">
      <p className="text-xs text-neutral-500">One traceable operational transaction chain -- accepted quote through Job Order, Shipment, ePOD/cost, profitability and billing readiness.</p>

      {manifest.shipments.length === 0 ? (
        <p className="text-sm text-neutral-500">No Shipment Orders yet.</p>
      ) : (
        <ul className="flex flex-col gap-2">
          {manifest.shipments.map((shipment) => (
            <li key={shipment.shipmentOrderId} className="rounded border border-neutral-200 p-2 text-sm">
              <div className="flex flex-wrap items-center gap-2">
                <span className="font-medium text-neutral-900">{shipment.shipmentNumber}</span>
                <StatusBadge tone="neutral" label={shipment.status} />
                {shipment.milestone ? <StatusBadge tone={shipment.milestone.isDelayed ? "warning" : "neutral"} label={shipment.milestone.lastMilestoneCode ?? "no milestone yet"} /> : null}
              </div>
              <dl className="mt-1 grid grid-cols-2 gap-x-4 gap-y-1 text-xs text-neutral-600">
                <dt>ePOD</dt>
                <dd>{shipment.epod ? `${shipment.epod.status} (v${shipment.epod.versionNumber})` : "not started"}</dd>
                <dt>Actual cost</dt>
                <dd>{shipment.actualCost ? `${shipment.actualCost.status} (v${shipment.actualCost.versionNumber})` : "not started"}</dd>
              </dl>
            </li>
          ))}
        </ul>
      )}

      <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
        <dt className="text-neutral-600">Profitability</dt>
        <dd className="text-neutral-900">{manifest.profitability ? `${manifest.profitability.status} (v${manifest.profitability.versionNumber})` : "not calculated"}</dd>
        <dt className="text-neutral-600">Billing readiness</dt>
        <dd className="text-neutral-900">{manifest.billingReadiness ? `${manifest.billingReadiness.effectiveStatus} (v${manifest.billingReadiness.versionNumber})` : "not evaluated"}</dd>
      </dl>

      {manifest.edges.length > 0 ? (
        <div className="border-t border-neutral-200 pt-2">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Captured lineage edges</h3>
          <ul className="flex flex-col gap-1">
            {manifest.edges.map((edge) => (
              <li key={edge.id} className="text-xs text-neutral-700">
                {RELATION_LABELS[edge.relationType]} ({edge.sourceId.slice(0, 8)}… → {edge.targetId.slice(0, 8)}…)
                {edge.isOverride ? <span className="ml-1 text-neutral-500">-- override: {edge.overrideReason}</span> : null}
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <form action={overrideFormAction} className="flex flex-col gap-2 border-t border-neutral-200 pt-2" noValidate>
        <h3 className="text-xs font-semibold uppercase tracking-wide text-neutral-500">Add a corrective lineage mapping</h3>
        <p className="text-xs text-neutral-500">Bounded, reasoned, audited -- adds an additional mapping without deleting any prior evidence. Requires OPS:Override.</p>
        <label className="flex flex-col text-sm text-neutral-700">
          Relation
          <select name="relationType" className="rounded border border-neutral-300 px-2 py-1" defaultValue="job_to_shipment">
            {(Object.keys(RELATION_LABELS) as TransactionLineageRelationType[]).map((relationType) => (
              <option key={relationType} value={relationType}>
                {RELATION_LABELS[relationType]}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col text-sm text-neutral-700">
          Source ID
          <input type="text" name="sourceId" required className="rounded border border-neutral-300 px-2 py-1" />
        </label>
        <label className="flex flex-col text-sm text-neutral-700">
          Target ID
          <input type="text" name="targetId" required className="rounded border border-neutral-300 px-2 py-1" />
        </label>
        <label className="flex flex-col text-sm text-neutral-700">
          Reason
          <input type="text" name="reason" required className="rounded border border-neutral-300 px-2 py-1" />
        </label>
        <Button type="submit" loading={overridePending} loadingLabel="Recording…" variant="secondary">
          Record correction
        </Button>
        {overrideState.error ? (
          <p role="alert" className="text-sm text-danger">
            {overrideState.error}
          </p>
        ) : null}
      </form>
    </div>
  );
}
