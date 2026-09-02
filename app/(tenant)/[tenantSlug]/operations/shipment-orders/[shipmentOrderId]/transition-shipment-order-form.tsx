"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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
  const describedBy = state.error ? "transition-shipment-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <FormField id="transition-to-status" label="Move to">
        <Select
          id="transition-to-status"
          name="toStatus"
          className="w-64"
          defaultValue={permittedNextStatuses[0]}
          onChange={(event) => setSelectedStatus(event.target.value as TransitionableStatus)}
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        >
          {permittedNextStatuses.map((status) => (
            <option key={status} value={status}>
              {STATUS_LABELS[status] ?? status}
            </option>
          ))}
        </Select>
      </FormField>

      {reasonRequired ? (
        <FormField id="transition-reason" label="Reason (required)">
          <Input id="transition-reason" name="reason" type="text" required minLength={1} className="w-96" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      ) : null}

      {evidenceRequired ? (
        <FormField id="transition-evidence-ref" label="Evidence reference (required)">
          <Input id="transition-evidence-ref" name="evidenceRef" type="text" required minLength={1} className="w-96" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      ) : null}

      {state.error ? <ValidationMessage id="transition-shipment-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Transitioning…" className="w-fit">
        Apply transition
      </Button>
    </form>
  );
}
