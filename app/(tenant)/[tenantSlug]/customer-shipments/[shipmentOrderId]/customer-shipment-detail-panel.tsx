"use client";

import { useActionState } from "react";
import { Link } from "../../../../../components/ui/link.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { CustomerShipmentOrderActionState } from "../actions.ts";
import type { ShipmentOrderStatus, CustomerShipmentOrder, ShipmentChangeRequestStatus, CustomerShipmentChangeRequest } from "../../../../../server/contracts/customer-shipment-order/customer-shipment-order.ts";

const INITIAL_STATE: CustomerShipmentOrderActionState = { error: null };

// CPL-324 Tier C fix (integrated verification): widened to cover
// app.shipment_orders_status_check's own full canonical lifecycle -- the
// original 3-value map (draft/confirmed/cancelled) predates OPS-170's own
// lifecycle broadening and left every mid-lifecycle status unrenderable.
// Tone/label choices for the 8 new entries mirror components/domain/
// status-tone-map.ts's own SHIPMENT_ORDER_STATUS_TONE_MAP (the staff-facing
// shipment-order list's own already-correct, already-shipped mapping for
// the identical status set) for visual consistency across the two surfaces;
// the original three entries are left byte-identical to avoid an
// unnecessary, out-of-scope visual change to already-correct behavior.
const SHIPMENT_STATUS_TONE: Record<ShipmentOrderStatus, StatusTone> = {
  draft: "neutral",
  confirmed: "success",
  planned: "info",
  assigned: "info",
  dispatched: "info",
  in_transit: "warning",
  delivered: "success",
  epod: "success",
  closed: "success",
  held: "warning",
  cancelled: "danger",
};

const SHIPMENT_STATUS_LABEL: Record<ShipmentOrderStatus, string> = {
  draft: "draft",
  confirmed: "confirmed",
  planned: "planned",
  assigned: "assigned",
  dispatched: "dispatched",
  in_transit: "in transit",
  delivered: "delivered",
  epod: "ePOD received",
  closed: "closed",
  held: "held",
  cancelled: "cancelled",
};

const REQUEST_STATUS_TONE: Record<ShipmentChangeRequestStatus, StatusTone> = {
  submitted: "info",
  acknowledged: "warning",
  resolved: "success",
  rejected: "danger",
};

const REQUEST_STATUS_LABEL: Record<ShipmentChangeRequestStatus, string> = {
  submitted: "submitted",
  acknowledged: "acknowledged",
  resolved: "resolved",
  rejected: "rejected",
};

const REQUEST_TYPE_LABEL: Record<string, string> = {
  reschedule: "Reschedule",
  cancel: "Cancellation",
  other: "Other",
};

function snapshotText(snapshot: Record<string, unknown>): string {
  const candidates = ["name", "label", "company", "contactName"];
  for (const key of candidates) {
    const value = snapshot[key];
    if (typeof value === "string" && value.length > 0) return value;
  }
  return Object.keys(snapshot).length === 0 ? "Not specified" : JSON.stringify(snapshot);
}

function ChangeRequestRow({ request }: { request: CustomerShipmentChangeRequest }) {
  return (
    <li className="flex flex-col gap-1 rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium text-neutral-900">{REQUEST_TYPE_LABEL[request.requestType] ?? request.requestType}</span>
        <StatusBadge tone={REQUEST_STATUS_TONE[request.status]} label={REQUEST_STATUS_LABEL[request.status]} />
        <span className="text-xs text-neutral-400">{new Date(request.createdAt).toLocaleString()}</span>
      </div>
      <p className="text-sm text-neutral-700">{request.details}</p>
      {request.staffResponse ? (
        <p className="rounded bg-neutral-50 p-2 text-xs text-neutral-700">
          <span className="font-medium">Response{request.staffRespondedAt ? ` — ${new Date(request.staffRespondedAt).toLocaleString()}` : ""}: </span>
          {request.staffResponse}
        </p>
      ) : (
        <p className="text-xs text-neutral-400">Awaiting a response from your account team.</p>
      )}
    </li>
  );
}

function RequestChangeForm({
  tenantSlug,
  requestChangeAction,
}: {
  tenantSlug: string;
  requestChangeAction: (prevState: CustomerShipmentOrderActionState, formData: FormData) => Promise<CustomerShipmentOrderActionState>;
}) {
  const [state, formAction, pending] = useActionState(requestChangeAction, INITIAL_STATE);
  const errorId = "request-change-error";
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Request a change</h2>
      <FormField id="request-change-type" label={<span className="text-xs text-neutral-500">Request type</span>}>
        <Select id="request-change-type" name="requestType" required defaultValue="reschedule" aria-describedby={describedBy}>
          <option value="reschedule">Reschedule</option>
          <option value="cancel">Cancellation</option>
          <option value="other">Other</option>
        </Select>
      </FormField>
      <FormField id="request-change-details" label={<span className="text-xs text-neutral-500">Details (required)</span>}>
        <Textarea id="request-change-details" name="details" required rows={3} placeholder="Describe what you need changed" aria-describedby={describedBy} />
      </FormField>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Submitting…">
          Submit request
        </Button>
      </div>
      <p className="text-xs text-neutral-500">
        This does not change the shipment directly -- your account team reviews every request. Operations remains the sole owner of shipment execution. You can also{" "}
        <Link href={`/${tenantSlug}/customer-tickets`}>open a ticket</Link> for anything more urgent.
      </p>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function CustomerShipmentDetailPanel({
  tenantSlug,
  detail,
  changeRequests,
  requestChangeAction,
}: {
  tenantSlug: string;
  detail: CustomerShipmentOrder;
  changeRequests: readonly CustomerShipmentChangeRequest[];
  requestChangeAction: (prevState: CustomerShipmentOrderActionState, formData: FormData) => Promise<CustomerShipmentOrderActionState>;
}) {
  return (
    <div className="flex flex-col gap-4">
      <header className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center gap-2">
          <h1 className="text-lg font-semibold text-neutral-900">{detail.shipmentNumber}</h1>
          <StatusBadge tone={SHIPMENT_STATUS_TONE[detail.status]} label={SHIPMENT_STATUS_LABEL[detail.status]} />
        </div>
        <dl className="grid grid-cols-2 gap-2 text-xs text-neutral-500 sm:grid-cols-4">
          <div>
            <dt className="font-medium">Route</dt>
            <dd>
              {detail.origin} → {detail.destination}
            </dd>
          </div>
          <div>
            <dt className="font-medium">Mode / service</dt>
            <dd>
              {detail.mode} / {detail.serviceType}
            </dd>
          </div>
          <div>
            <dt className="font-medium">Planned pickup</dt>
            <dd>{detail.plannedPickupAt ? new Date(detail.plannedPickupAt).toLocaleString() : "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Planned delivery</dt>
            <dd>{detail.plannedDeliveryAt ? new Date(detail.plannedDeliveryAt).toLocaleString() : "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Consignee</dt>
            <dd>{snapshotText(detail.consigneeSnapshot)}</dd>
          </div>
          <div>
            <dt className="font-medium">Cargo</dt>
            <dd>{snapshotText(detail.cargoServiceSnapshot)}</dd>
          </div>
          <div>
            <dt className="font-medium">Allocated quantity</dt>
            <dd>{detail.allocatedQuantity ?? "—"}</dd>
          </div>
          <div>
            <dt className="font-medium">Allocated weight / volume</dt>
            <dd>
              {detail.allocatedWeightKg ?? "—"} kg / {detail.allocatedVolumeCbm ?? "—"} cbm
            </dd>
          </div>
        </dl>
        {detail.status === "cancelled" ? <p className="rounded bg-danger/10 p-2 text-sm text-neutral-800">This shipment has been cancelled by Operations.</p> : null}
        {detail.status === "confirmed" ? (
          <p className="rounded bg-success/10 p-2 text-sm text-neutral-800">
            This shipment is confirmed and immutable from the portal. To change pickup/delivery details or request cancellation, submit a change request below -- Operations reviews every request.
          </p>
        ) : null}
      </header>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Your change requests</h2>
        {changeRequests.length === 0 ? (
          <EmptyState title="No change requests yet" description="Requests you submit for this shipment, and any response from your account team, appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {changeRequests.map((r) => (
              <ChangeRequestRow key={r.id} request={r} />
            ))}
          </ul>
        )}
      </section>

      <RequestChangeForm tenantSlug={tenantSlug} requestChangeAction={requestChangeAction} />
    </div>
  );
}
