/**
 * Fleet Control Tower contract (ATW-226H, Prompt 226 decomposition child). Mirrors
 * supabase/migrations/20260730100000_create_advanced_tms_fleet_control_tower.sql's
 * three new tenant-wide aggregating reads: app.get_tenant_vehicle_tracking_overview,
 * app.get_tenant_pending_milestone_candidates, app.get_tenant_pending_exception_signals.
 *
 * No mutation wrappers exist in this module -- every write path this UI needs already
 * exists (server/mutations/{fleet-driver-device,tracking-source-policy,geofence-route-
 * deviation-signals}.ts); this is a read-only aggregation layer over already-real data.
 */

import { z } from "zod";
import { TelemetrySourceTypeSchema } from "../canonical-telemetry/canonical-telemetry.ts";

const FleetControlTowerGeoJsonPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: z.tuple([z.number(), z.number()]),
});

export const TenantVehicleTrackingOverviewRowSchema = z.object({
  vehicleMasterId: z.string().uuid(),
  vehicleCode: z.string(),
  vehicleName: z.string(),
  mobileTrackingEligible: z.boolean(),
  directDeviceTrackingEligible: z.boolean(),
  thirdPartyTrackingEligible: z.boolean(),
  currentSourceType: TelemetrySourceTypeSchema.nullable(),
  currentLocation: FleetControlTowerGeoJsonPointSchema.nullable(),
  currentSpeedKmh: z.number().nullable(),
  currentHeadingDegrees: z.number().nullable(),
  currentEventAt: z.string().nullable(),
  currentReceivedAt: z.string().nullable(),
});
export type TenantVehicleTrackingOverviewRow = z.infer<typeof TenantVehicleTrackingOverviewRowSchema>;

/** A vehicle never yet tracked carries null current* fields, not a missing row. */
export function parseTenantVehicleTrackingOverviewRow(row: Record<string, unknown>): TenantVehicleTrackingOverviewRow {
  return TenantVehicleTrackingOverviewRowSchema.parse({
    vehicleMasterId: row.vehicle_master_id,
    vehicleCode: row.vehicle_code,
    vehicleName: row.vehicle_name,
    mobileTrackingEligible: row.mobile_tracking_eligible,
    directDeviceTrackingEligible: row.direct_device_tracking_eligible,
    thirdPartyTrackingEligible: row.third_party_tracking_eligible,
    currentSourceType: row.current_source_type ?? null,
    currentLocation: row.current_location_geojson ?? null,
    currentSpeedKmh: row.current_speed_kmh === null || row.current_speed_kmh === undefined ? null : Number(row.current_speed_kmh),
    currentHeadingDegrees: row.current_heading_degrees === null || row.current_heading_degrees === undefined ? null : Number(row.current_heading_degrees),
    currentEventAt: row.current_event_at ?? null,
    currentReceivedAt: row.current_received_at ?? null,
  });
}

export const TenantPendingMilestoneCandidateRowSchema = z.object({
  id: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  shipmentNumber: z.string(),
  shipmentLegId: z.string().uuid(),
  shipmentLegStopId: z.string().uuid(),
  milestoneCode: z.string(),
  candidateEventTime: z.string(),
  detectedAt: z.string(),
  location: FleetControlTowerGeoJsonPointSchema.nullable(),
});
export type TenantPendingMilestoneCandidateRow = z.infer<typeof TenantPendingMilestoneCandidateRowSchema>;

export function parseTenantPendingMilestoneCandidateRow(row: Record<string, unknown>): TenantPendingMilestoneCandidateRow {
  return TenantPendingMilestoneCandidateRowSchema.parse({
    id: row.id,
    shipmentOrderId: row.shipment_order_id,
    shipmentNumber: row.shipment_number,
    shipmentLegId: row.shipment_leg_id,
    shipmentLegStopId: row.shipment_leg_stop_id,
    milestoneCode: row.milestone_code,
    candidateEventTime: row.candidate_event_time,
    detectedAt: row.detected_at,
    location: row.location_geojson ?? null,
  });
}

export const TenantPendingExceptionSignalRowSchema = z.object({
  id: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  shipmentNumber: z.string(),
  shipmentLegId: z.string().uuid(),
  signalType: z.string(),
  exceptionType: z.string(),
  severity: z.string(),
  detectedAt: z.string(),
  description: z.string(),
  location: FleetControlTowerGeoJsonPointSchema.nullable(),
});
export type TenantPendingExceptionSignalRow = z.infer<typeof TenantPendingExceptionSignalRowSchema>;

export function parseTenantPendingExceptionSignalRow(row: Record<string, unknown>): TenantPendingExceptionSignalRow {
  return TenantPendingExceptionSignalRowSchema.parse({
    id: row.id,
    shipmentOrderId: row.shipment_order_id,
    shipmentNumber: row.shipment_number,
    shipmentLegId: row.shipment_leg_id,
    signalType: row.signal_type,
    exceptionType: row.exception_type,
    severity: row.severity,
    detectedAt: row.detected_at,
    description: row.description,
    location: row.location_geojson ?? null,
  });
}

export const GetTenantVehicleTrackingOverviewInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetTenantVehicleTrackingOverviewInput = z.input<typeof GetTenantVehicleTrackingOverviewInputSchema>;

export const GetTenantPendingSignalsInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  limit: z.number().int().positive().default(50),
});
export type GetTenantPendingSignalsInput = z.input<typeof GetTenantPendingSignalsInputSchema>;
