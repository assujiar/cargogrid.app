import { notFound } from "next/navigation";
import { randomUUID } from "node:crypto";
import { resolveOperationsAccessForRequest } from "../../../../../../lib/portal/resolve-operations-access.server.ts";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { getShipmentOrder, getJobShipmentAllocationBalance, ShipmentOrderQueryError } from "../../../../../../server/queries/shipment-order.ts";
import { getShipmentStatusHistory, ShipmentLifecycleQueryError } from "../../../../../../server/queries/shipment-lifecycle.ts";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { Badge } from "../../../../../../components/ui/badge.tsx";
import { SHIPMENT_ORDER_STATUS_TONE_MAP } from "../../../../../../components/domain/status-tone-map.ts";
import { ErrorState } from "../../../../../../components/ui/error-state.tsx";
import { ConfirmShipmentOrderForm } from "./confirm-shipment-order-form.tsx";
import { TransitionShipmentOrderForm } from "./transition-shipment-order-form.tsx";
import { StatusTimeline } from "./status-timeline.tsx";
import { confirmShipmentOrderAction, transitionShipmentOrderAction, type ShipmentOrderFormState } from "./actions.ts";
import { permittedNextStatuses } from "./lifecycle-transitions.ts";
import type { TransitionableStatus } from "../../../../../../server/contracts/shipment-lifecycle/shipment-lifecycle.ts";

/**
 * Shipment Order detail (OPS-169, CG-S8-OPS-003, Prompt 169 §15) -- inherited fields
 * with source links (Job Order, shipper account), route/schedule, and the governed
 * allocation balance for the Job Order this Shipment Order shares with any sibling
 * splits. `getShipmentOrder` returns `null` for both "does not exist" and "exists but
 * RLS denies it," matching every prior detail page's posture.
 */
export default async function ShipmentOrderDetailPage({ params }: { params: Promise<{ tenantSlug: string; shipmentOrderId: string }> }) {
  const { tenantSlug, shipmentOrderId } = await params;
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  const supabase = await createSupabaseServerClient();

  let shipment;
  try {
    shipment = await getShipmentOrder(supabase, shipmentOrderId);
  } catch (error) {
    if (!(error instanceof ShipmentOrderQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading this Shipment Order. Please try again." />;
  }

  if (!shipment || shipment.tenantId !== access.tenant.id) {
    notFound();
  }

  let balance;
  try {
    balance = await getJobShipmentAllocationBalance(supabase, { jobOrderId: shipment.jobOrderId, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ShipmentOrderQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the allocation balance. Please try again." />;
  }

  let history;
  try {
    history = await getShipmentStatusHistory(supabase, { shipmentOrderId: shipment.id, actorAuthUserId: access.authUserId });
  } catch (error) {
    if (!(error instanceof ShipmentLifecycleQueryError)) {
      throw error;
    }
    return <ErrorState description="Something went wrong loading the status history. Please try again." />;
  }

  const { tone, label } = SHIPMENT_ORDER_STATUS_TONE_MAP[shipment.status];
  const consignee = shipment.consigneeSnapshot as { legal_name?: string; contact_name?: string };
  const boundConfirmAction = confirmShipmentOrderAction.bind(null, tenantSlug, shipment.id, shipment.recordVersion);
  const transitionIdempotencyKey = randomUUID();
  const boundTransitionAction = (
    toStatus: TransitionableStatus,
    reason: string,
    evidenceRef: string,
    prevState: ShipmentOrderFormState,
    formData: FormData,
  ) => transitionShipmentOrderAction(tenantSlug, shipment.id, shipment.recordVersion, transitionIdempotencyKey, toStatus, reason, evidenceRef, prevState, formData);
  const nextStatuses = permittedNextStatuses(shipment.status, shipment.heldFromStatus);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center gap-3">
        <h1 className="text-xl font-semibold text-neutral-900">{shipment.shipmentNumber}</h1>
        <StatusBadge tone={tone} label={label} />
        <Badge tone="neutral">{shipment.mode}</Badge>
      </div>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Source lineage</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Job Order</dt>
          <dd className="text-neutral-900">
            <a href={`/${tenantSlug}/operations/job-orders/${shipment.jobOrderId}`} className="text-primary underline">
              {shipment.jobOrderId}
            </a>
          </dd>
          <dt className="text-neutral-600">Shipper account</dt>
          <dd className="text-neutral-900">{shipment.shipperAccountId}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Route and schedule</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Origin</dt>
          <dd className="text-neutral-900">{shipment.origin}</dd>
          <dt className="text-neutral-600">Destination</dt>
          <dd className="text-neutral-900">{shipment.destination}</dd>
          <dt className="text-neutral-600">Planned pickup</dt>
          <dd className="text-neutral-900">{shipment.plannedPickupAt ? new Date(shipment.plannedPickupAt).toLocaleString() : "—"}</dd>
          <dt className="text-neutral-600">Planned delivery</dt>
          <dd className="text-neutral-900">{shipment.plannedDeliveryAt ? new Date(shipment.plannedDeliveryAt).toLocaleString() : "—"}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Consignee</h2>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">Legal name</dt>
          <dd className="text-neutral-900">{consignee.legal_name ?? "—"}</dd>
          <dt className="text-neutral-600">Contact</dt>
          <dd className="text-neutral-900">{consignee.contact_name ?? "—"}</dd>
        </dl>
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Allocation</h2>
        <dl className="grid grid-cols-3 gap-x-4 gap-y-1 text-sm">
          <dt className="text-neutral-600">This shipment (qty)</dt>
          <dd className="text-neutral-900">{shipment.allocatedQuantity ?? "—"}</dd>
          <dt className="text-neutral-600">Job total (qty)</dt>
          <dd className="text-neutral-900">{balance.basisQuantity ?? "—"}</dd>
          <dt className="text-neutral-600">Job remaining (qty)</dt>
          <dd className="text-neutral-900">{balance.remainingQuantity ?? "—"}</dd>
        </dl>
        {shipment.splitReason ? <p className="text-xs text-neutral-500">Split reason: {shipment.splitReason}</p> : null}
      </section>

      {shipment.status === "draft" ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Confirm</h2>
          <ConfirmShipmentOrderForm action={boundConfirmAction} />
        </section>
      ) : null}

      {nextStatuses.length > 0 ? (
        <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Transition</h2>
          {shipment.status === "closed" ? (
            <p className="text-xs text-neutral-500">Reopening a closed shipment is a Supreme Admin-only correction (RPD-022).</p>
          ) : null}
          <TransitionShipmentOrderForm action={boundTransitionAction} permittedNextStatuses={nextStatuses} />
        </section>
      ) : null}

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Status timeline</h2>
        <StatusTimeline history={history} />
      </section>
    </div>
  );
}
