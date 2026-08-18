/**
 * Customer Shipment Tracking contract (CPL-305, CG-S13-CPL-007, Prompt 305).
 * Mirrors supabase/migrations/20260801060000_create_customer_portal_
 * shipment_tracking.sql's single RPC, app.get_customer_shipment_tracking --
 * a pure read composition over already-canonical Operations/Advanced-TMS
 * data (milestone timeline, arbitrated vehicle position, ETA, freshness
 * marker). No write surface exists in this capability.
 *
 * `milestones` array elements already carry camelCase keys -- the RPC's own
 * `jsonb_build_object('code', ..., 'name', ..., 'category', ..., 'eventTime',
 * ...)` projection, mirroring app.lookup_public_shipment_tracking's
 * identical `code`/`eventTime` shape (plus `name`/`category` for a readable
 * authenticated UI) -- so no snake_case remapping is needed for that field.
 */

import { z } from "zod";

export const CustomerShipmentTrackingMilestoneSchema = z.object({
  code: z.string(),
  name: z.string(),
  category: z.string(),
  eventTime: z.string(),
});
export type CustomerShipmentTrackingMilestone = z.infer<typeof CustomerShipmentTrackingMilestoneSchema>;

export const VEHICLE_POSITION_STATUSES = ["live", "delayed", "unavailable"] as const;
export const VehiclePositionStatusSchema = z.enum(VEHICLE_POSITION_STATUSES);
export type VehiclePositionStatus = z.infer<typeof VehiclePositionStatusSchema>;

export const ETA_STATUSES = ["on_time", "delayed", "unavailable"] as const;
export const EtaStatusSchema = z.enum(ETA_STATUSES);
export type EtaStatus = z.infer<typeof EtaStatusSchema>;

export const POSITION_UNAVAILABLE_REASONS = ["tracking_not_entitled", "no_active_leg", "no_vehicle_assigned", "not_customer_visible", "no_live_position"] as const;
export const PositionUnavailableReasonSchema = z.enum(POSITION_UNAVAILABLE_REASONS);
export type PositionUnavailableReason = z.infer<typeof PositionUnavailableReasonSchema>;

export const CustomerShipmentTrackingSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  milestones: z.array(CustomerShipmentTrackingMilestoneSchema),
  trackingEntitled: z.boolean(),
  positionUnavailableReason: PositionUnavailableReasonSchema.nullable(),
  vehiclePositionGeojson: z.record(z.string(), z.unknown()).nullable(),
  vehiclePositionUpdatedAt: z.string().nullable(),
  vehiclePositionStatus: VehiclePositionStatusSchema.nullable(),
  etaStatus: EtaStatusSchema.nullable(),
  etaAt: z.string().nullable(),
});
export type CustomerShipmentTracking = z.infer<typeof CustomerShipmentTrackingSchema>;

export function parseCustomerShipmentTracking(row: Record<string, unknown>): CustomerShipmentTracking {
  return CustomerShipmentTrackingSchema.parse({
    shipmentOrderId: row.shipment_order_id,
    milestones: row.milestones ?? [],
    trackingEntitled: row.tracking_entitled,
    positionUnavailableReason: row.position_unavailable_reason ?? null,
    vehiclePositionGeojson: row.vehicle_position_geojson ?? null,
    vehiclePositionUpdatedAt: row.vehicle_position_updated_at ?? null,
    vehiclePositionStatus: row.vehicle_position_status ?? null,
    etaStatus: row.eta_status ?? null,
    etaAt: row.eta_at ?? null,
  });
}
