"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import type { TransitionableStatus } from "../../../../../../server/contracts/shipment-lifecycle/shipment-lifecycle.ts";
import { REASON_REQUIRED_STATUSES, EVIDENCE_REQUIRED_STATUSES } from "./lifecycle-transitions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const STATUS_LABELS: Partial<Record<TransitionableStatus, string>> = {
  planned: "Planned",
  assigned: "Assigned",
  dispatched: "Dispatched",
  in_transit: "In transit",
  delivered: "Delivered",
  epod: "ePOD received",
  closed: "Closed",
  held: "Hold",
  cancelled: "Cancel",
};

/**
 * The one canonical transition control (OPS-170) -- permitted next states only
 * (restated client-side for affordance, never authoritative; the database
 * re-validates every edge regardless). Reason capture is shown when the selected
 * target requires one (held/cancelled); evidence capture is shown when the target
 * requires it (delivered/epod/closed) -- both are server-enforced too, this is UI
 * guidance only.
 */
export function TransitionShipmentOrderForm({
  action,
  permittedNextStatuses,
}: {
  action: (toStatus: TransitionableStatus, reason: string, evidenceRef: string, prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  permittedNextStatuses: readonly TransitionableStatus[];
}) {
  const [selectedStatus, setSelectedStatus] = useState<TransitionableStatus | undefined>(permittedNextStatuses[0]);
  const [state, formAction, pending] = useActionState(
    async (prevState: ShipmentOrderFormState, formData: FormData) => {
      const toStatus = String(formData.get("toStatus")) as TransitionableStatus;
      const reason = String(formData.get("reason") ?? "");
      const evidenceRef = String(formData.get("evidenceRef") ?? "");
      return action(toStatus, reason, evidenceRef, prevState, formData);
    },
    INITIAL_STATE,
  );

  if (permittedNextStatuses.length === 0) {
    return null;
  }

  const reasonRequired = selectedStatus ? REASON_REQUIRED_STATUSES.includes(selectedStatus) : false;
  const evidenceRequired = selectedStatus ? EVIDENCE_REQUIRED_STATUSES.includes(selectedStatus) : false;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="flex flex-col gap-1">
        <label htmlFor="toStatus" className="text-sm font-medium text-neutral-700">
          Move to
        </label>
        <select
          id="toStatus"
          name="toStatus"
          className="w-64 rounded-md border border-neutral-300 px-3 py-2 text-sm"
          defaultValue={permittedNextStatuses[0]}
          onChange={(event) => setSelectedStatus(event.target.value as TransitionableStatus)}
        >
          {permittedNextStatuses.map((status) => (
            <option key={status} value={status}>
              {STATUS_LABELS[status] ?? status}
            </option>
          ))}
        </select>
      </div>

      {reasonRequired ? (
        <div className="flex flex-col gap-1">
          <label htmlFor="reason" className="text-sm font-medium text-neutral-700">
            Reason (required)
          </label>
          <input id="reason" name="reason" type="text" required minLength={1} className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      ) : null}

      {evidenceRequired ? (
        <div className="flex flex-col gap-1">
          <label htmlFor="evidenceRef" className="text-sm font-medium text-neutral-700">
            Evidence reference (required)
          </label>
          <input id="evidenceRef" name="evidenceRef" type="text" required minLength={1} className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      ) : null}

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Transitioning…" className="w-fit">
        Apply transition
      </Button>
    </form>
  );
}
