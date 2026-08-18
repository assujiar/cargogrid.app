/**
 * Customer shipment tracking/timeline section (CPL-305, CG-S13-CPL-007,
 * Prompt 305). Renders app.get_customer_shipment_tracking's own composed
 * response -- extends the existing customer-shipments/[shipmentOrderId]
 * detail page (CPL-304) with a new sub-component, per the orchestrating
 * task's own design decision 7, rather than a new sibling route.
 *
 * Exception banners and ePOD/document actions named in the source prompt's
 * own §15 UI/UX impact are deliberately NOT built here -- Shipment
 * Monitoring (Prompt 306), ePOD Access (Prompt 307), and Document Center
 * (Prompt 308) are this same batch's own next capabilities, explicitly
 * chartered for exactly that surface. Composing that data into this
 * checkpoint's own RPC would risk the "duplicate composition, second
 * independently-evolving read path" anti-pattern ADR-0024 Part A already
 * rejected once (docs/build-log/phase-08/CPL-305.md §9 discloses this
 * boundary explicitly, per RECURRING_DEFECT_TAXONOMY.md C-23).
 */

import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { CustomerShipmentTrackingMap } from "./customer-shipment-tracking-map.tsx";
import type { CustomerShipmentTracking, VehiclePositionStatus, EtaStatus, PositionUnavailableReason } from "../../../../../server/contracts/customer-shipment-tracking/customer-shipment-tracking.ts";

const VEHICLE_STATUS_TONE: Record<VehiclePositionStatus, StatusTone> = {
  live: "success",
  delayed: "warning",
  unavailable: "neutral",
};
const VEHICLE_STATUS_LABEL: Record<VehiclePositionStatus, string> = {
  live: "Live",
  delayed: "Delayed signal",
  unavailable: "Signal unavailable",
};

const ETA_STATUS_TONE: Record<EtaStatus, StatusTone> = {
  on_time: "success",
  delayed: "warning",
  unavailable: "neutral",
};
const ETA_STATUS_LABEL: Record<EtaStatus, string> = {
  on_time: "On time",
  delayed: "Delayed",
  unavailable: "Unavailable",
};

// Alternative flow (source prompt §22): "when data is stale/incomplete, show
// last trusted update... do not fabricate live status" -- one honest,
// specific message per disclosed reason, never a generic "unavailable" blob.
const UNAVAILABLE_REASON_MESSAGE: Record<PositionUnavailableReason, string> = {
  tracking_not_entitled: "Live tracking isn't included in your current plan. Contact your account team to enable it.",
  no_active_leg: "This shipment doesn't have a leg in transit right now.",
  no_vehicle_assigned: "No vehicle is currently assigned to this shipment yet.",
  not_customer_visible: "Live position isn't shared for this leg.",
  no_live_position: "We haven't received a live position for this vehicle yet.",
};

const MILESTONE_CATEGORY_LABEL: Record<string, string> = {
  pickup: "Pickup",
  in_transit: "In transit",
  exception: "Exception",
  delivery: "Delivery",
  administrative: "Administrative",
};

export function CustomerShipmentTrackingPanel({ tracking }: { tracking: CustomerShipmentTracking }) {
  const hasPosition = tracking.vehiclePositionGeojson !== null && tracking.vehiclePositionStatus !== null;

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <h2 className="text-sm font-semibold text-neutral-900">Live tracking</h2>
          {tracking.vehiclePositionStatus ? <StatusBadge tone={VEHICLE_STATUS_TONE[tracking.vehiclePositionStatus]} label={VEHICLE_STATUS_LABEL[tracking.vehiclePositionStatus]} /> : null}
        </div>

        {hasPosition ? (
          <div className="flex flex-col gap-2">
            <CustomerShipmentTrackingMap position={tracking.vehiclePositionGeojson as { type: string; coordinates: [number, number] }} />
            {tracking.vehiclePositionUpdatedAt ? <p className="text-xs text-neutral-500">Last updated {new Date(tracking.vehiclePositionUpdatedAt).toLocaleString()}</p> : null}
            {tracking.etaStatus ? (
              <div className="flex flex-wrap items-center gap-2 text-sm text-neutral-700">
                <StatusBadge tone={ETA_STATUS_TONE[tracking.etaStatus]} label={`ETA: ${ETA_STATUS_LABEL[tracking.etaStatus]}`} />
                {tracking.etaAt ? <span>{new Date(tracking.etaAt).toLocaleString()}</span> : null}
              </div>
            ) : null}
          </div>
        ) : (
          <EmptyState title="No live position right now" description={tracking.positionUnavailableReason ? UNAVAILABLE_REASON_MESSAGE[tracking.positionUnavailableReason] : "A live position will appear here once available."} />
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Timeline</h2>
        {tracking.milestones.length === 0 ? (
          <EmptyState title="No milestones yet" description="Tracked milestones for this shipment will appear here as they happen." />
        ) : (
          <ol className="flex flex-col gap-2">
            {tracking.milestones.map((milestone, index) => (
              <li key={`${milestone.code}-${milestone.eventTime}-${index}`} className="flex flex-col gap-0.5 rounded-md border border-neutral-100 p-3">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="text-sm font-medium text-neutral-900">{milestone.name}</span>
                  <StatusBadge tone="neutral" label={MILESTONE_CATEGORY_LABEL[milestone.category] ?? milestone.category} />
                </div>
                <span className="text-xs text-neutral-400">{new Date(milestone.eventTime).toLocaleString()}</span>
              </li>
            ))}
          </ol>
        )}
      </section>
    </div>
  );
}
