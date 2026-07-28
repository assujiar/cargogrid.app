"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { BillingReadinessEvaluation, BillingReadinessHandoff } from "../../../../../../server/contracts/billing-readiness/billing-readiness.ts";
import type { JobOrderFormState } from "./actions.ts";

const INITIAL_STATE: JobOrderFormState = { error: null };

/** OPS-181: evidence status only -- never an invoice/AR/GL entry. Shows the current evaluation's exact blockers, an evaluate/reevaluate form, an override/revoke-override form (bounded to forcing not_ready -> effectively ready), and a Finance handoff action once effectively ready. */
export function BillingReadinessPanel({
  evaluation,
  handoffs,
  evaluateAction,
  overrideAction,
  revokeOverrideAction,
  handoffAction,
}: {
  readonly evaluation: BillingReadinessEvaluation | null;
  readonly handoffs: readonly BillingReadinessHandoff[];
  readonly evaluateAction: (prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState>;
  readonly overrideAction: (prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState>;
  readonly revokeOverrideAction: (prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState>;
  readonly handoffAction: (prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState>;
}) {
  const [evaluateState, evaluateFormAction, evaluatePending] = useActionState(evaluateAction, INITIAL_STATE);
  const [overrideState, overrideFormAction, overridePending] = useActionState(overrideAction, INITIAL_STATE);
  const [revokeState, revokeFormAction, revokePending] = useActionState(revokeOverrideAction, INITIAL_STATE);
  const [handoffState, handoffFormAction, handoffPending] = useActionState(handoffAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-3">
      <p className="text-xs text-neutral-500">Evidence status only -- never an invoice, accounts receivable, or general ledger entry.</p>

      {!evaluation ? (
        <p className="text-sm text-neutral-500">This Job Order has never been evaluated for billing readiness.</p>
      ) : (
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center gap-2">
            <StatusBadge tone={evaluation.effectiveStatus === "ready" ? "success" : "warning"} label={evaluation.effectiveStatus.replace("_", " ")} />
            <span className="text-xs text-neutral-500">v{evaluation.versionNumber}</span>
            {evaluation.isOverridden ? <StatusBadge tone="neutral" label="overridden" /> : null}
          </div>
          {evaluation.isOverridden && evaluation.overrideReason ? <p className="text-sm text-neutral-600">Override reason: {evaluation.overrideReason}</p> : null}
          {evaluation.blockers.length > 0 ? (
            <ul className="flex flex-col gap-1">
              {evaluation.blockers.map((blocker, index) => (
                <li key={index} className="text-sm text-neutral-700">
                  {blocker.code.replace(/_/g, " ")}
                  {typeof blocker.shipmentOrderId === "string" ? ` (shipment ${blocker.shipmentOrderId})` : ""}
                </li>
              ))}
            </ul>
          ) : (
            <p className="text-sm text-neutral-500">No blockers.</p>
          )}
        </div>
      )}

      <form action={evaluateFormAction} className="flex flex-wrap items-end gap-2" noValidate>
        {evaluation ? (
          <label className="flex flex-col text-sm text-neutral-700">
            Reevaluation reason (required to reevaluate)
            <input type="text" name="reevaluationReason" className="rounded border border-neutral-300 px-2 py-1" />
          </label>
        ) : null}
        <Button type="submit" loading={evaluatePending} loadingLabel="Evaluating…" variant="secondary">
          {evaluation ? "Reevaluate" : "Evaluate billing readiness"}
        </Button>
        {evaluateState.error ? (
          <p role="alert" className="w-full text-sm text-danger">
            {evaluateState.error}
          </p>
        ) : null}
      </form>

      {evaluation && evaluation.effectiveStatus === "not_ready" ? (
        <form action={overrideFormAction} className="flex flex-wrap items-end gap-2" noValidate>
          <label className="flex flex-col text-sm text-neutral-700">
            Override reason
            <input type="text" name="reason" required className="w-64 rounded border border-neutral-300 px-2 py-1" />
          </label>
          <Button type="submit" loading={overridePending} loadingLabel="Overriding…" variant="secondary">
            Override to ready
          </Button>
          {overrideState.error ? (
            <p role="alert" className="w-full text-sm text-danger">
              {overrideState.error}
            </p>
          ) : null}
        </form>
      ) : null}

      {evaluation && evaluation.isOverridden ? (
        <form action={revokeFormAction} className="flex flex-wrap items-end gap-2" noValidate>
          <label className="flex flex-col text-sm text-neutral-700">
            Revoke reason
            <input type="text" name="reason" required className="w-64 rounded border border-neutral-300 px-2 py-1" />
          </label>
          <Button type="submit" loading={revokePending} loadingLabel="Revoking…" variant="secondary">
            Revoke override
          </Button>
          {revokeState.error ? (
            <p role="alert" className="w-full text-sm text-danger">
              {revokeState.error}
            </p>
          ) : null}
        </form>
      ) : null}

      {evaluation && evaluation.effectiveStatus === "ready" ? (
        <form action={handoffFormAction}>
          <Button type="submit" loading={handoffPending} loadingLabel="Handing off…">
            Hand off to Finance
          </Button>
          {handoffState.error ? (
            <p role="alert" className="mt-1 text-sm text-danger">
              {handoffState.error}
            </p>
          ) : null}
        </form>
      ) : null}

      {handoffs.length > 0 ? (
        <div className="mt-2 border-t border-neutral-200 pt-2">
          <h3 className="mb-2 text-xs font-semibold uppercase tracking-wide text-neutral-500">Finance handoffs</h3>
          <ul className="flex flex-col gap-1">
            {handoffs.map((handoff) => (
              <li key={handoff.id} className="text-sm text-neutral-700">
                {new Date(handoff.handedOffAt).toLocaleString()} by {handoff.handedOffBy ?? handoff.handedOffByAuthUserId}
              </li>
            ))}
          </ul>
        </div>
      ) : null}
    </div>
  );
}
