/**
 * Advanced Milestone and Exception with Multi-Source Telemetry contract (ATW-228,
 * CG-S10-ATW-009). Mirrors
 * supabase/migrations/20260730130000_create_advanced_tms_milestone_exception_telemetry.sql's
 * app.shipment_leg_eta_projection composite shape, the app.get_shipment_leg_eta_
 * projection/app.rebaseline_shipment_leg_schedule RPCs.
 *
 * Confidence/freshness provenance on milestone/exception records themselves is not
 * re-declared here -- see the widened MilestoneEvent (server/contracts/milestone-
 * management) and OperationalException (server/contracts/exception-escalation)
 * schemas. Tracking-health signals reuse app.shipment_exception_signals (ATW-226G)
 * with a new signal_type -- see server/contracts/geofence-route-deviation-signals.
 */

import { z } from "zod";

export const SHIPMENT_LEG_ETA_UNCOMPUTABLE_REASONS = [
  "leg_not_found",
  "leg_not_active",
  "vehicle_not_assigned",
  "no_live_position",
  "position_stale",
  "no_remaining_stops",
] as const;
export const ShipmentLegEtaUncomputableReasonSchema = z.enum(SHIPMENT_LEG_ETA_UNCOMPUTABLE_REASONS);
export type ShipmentLegEtaUncomputableReason = z.infer<typeof ShipmentLegEtaUncomputableReasonSchema>;

export const SHIPMENT_LEG_ETA_POSITION_STATUSES = ["healthy", "stale", "offline"] as const;
export const ShipmentLegEtaPositionStatusSchema = z.enum(SHIPMENT_LEG_ETA_POSITION_STATUSES);
export type ShipmentLegEtaPositionStatus = z.infer<typeof ShipmentLegEtaPositionStatusSchema>;

export const ShipmentLegEtaProjectionSchema = z.object({
  shipmentLegId: z.string().uuid(),
  computable: z.boolean(),
  reason: ShipmentLegEtaUncomputableReasonSchema.nullable(),
  positionStatus: ShipmentLegEtaPositionStatusSchema.nullable(),
  remainingDistanceKm: z.coerce.number().nullable(),
  estimatedArrivalAt: z.string().nullable(),
  plannedArrivalAt: z.string().nullable(),
  delayMinutes: z.coerce.number().nullable(),
  downstreamLegCount: z.number().int().nonnegative(),
});
export type ShipmentLegEtaProjection = z.infer<typeof ShipmentLegEtaProjectionSchema>;

export function parseShipmentLegEtaProjection(row: Record<string, unknown>): ShipmentLegEtaProjection {
  return ShipmentLegEtaProjectionSchema.parse({
    shipmentLegId: row.shipment_leg_id,
    computable: row.computable,
    reason: row.reason ?? null,
    positionStatus: row.position_status ?? null,
    remainingDistanceKm: row.remaining_distance_km ?? null,
    estimatedArrivalAt: row.estimated_arrival_at ?? null,
    plannedArrivalAt: row.planned_arrival_at ?? null,
    delayMinutes: row.delay_minutes ?? null,
    downstreamLegCount: row.downstream_leg_count,
  });
}

export const GetShipmentLegEtaProjectionInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetShipmentLegEtaProjectionInput = z.input<typeof GetShipmentLegEtaProjectionInputSchema>;

export const RebaselineShipmentLegScheduleInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  newPlannedDepartureAt: z.string(),
  newPlannedArrivalAt: z.string(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RebaselineShipmentLegScheduleInput = z.input<typeof RebaselineShipmentLegScheduleInputSchema>;
