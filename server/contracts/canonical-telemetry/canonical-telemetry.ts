/**
 * Canonical telemetry, current position, source health, and source switches contract
 * (ATW-226F, CG-S10-ATW-006's family, Prompt 226 decomposition child). Mirrors
 * supabase/migrations/20260729390000_create_advanced_tms_canonical_telemetry_arbitration.sql's
 * app.canonical_telemetry_events/app.vehicle_current_positions/app.vehicle_source_health/
 * app.vehicle_source_switches shapes and the app.get_vehicle_current_position/
 * app.get_vehicle_telemetry_history/app.get_vehicle_source_health/app.get_vehicle_source_
 * switches read projections.
 *
 * No mutation wrappers exist in this module -- every write path into these tables is the
 * internal, service_role-only app.arbitrate_and_project_vehicle_position(), called only
 * from within the already-widened app.ingest_driver_mobile_report/app.ingest_direct_
 * device_telemetry_batch/app.ingest_third_party_provider_webhook_event (whose own TS
 * mutation wrappers -- server/mutations/{driver-mobile-tracking,gps-gateway-ingestion,
 * third-party-provider-adapter}.ts -- are unchanged, since none of those RPCs' own
 * signatures changed).
 */

import { z } from "zod";

export const TELEMETRY_SOURCE_TYPES = ["driver_mobile", "direct_device", "third_party_platform"] as const;
export const TelemetrySourceTypeSchema = z.enum(TELEMETRY_SOURCE_TYPES);
export type TelemetrySourceType = z.infer<typeof TelemetrySourceTypeSchema>;

export const VehicleCurrentPositionSchema = z.object({
  vehicleMasterId: z.string().uuid(),
  tenantId: z.string().uuid(),
  sourceType: TelemetrySourceTypeSchema,
  latitude: z.number(),
  longitude: z.number(),
  speedKmh: z.number().nullable(),
  headingDegrees: z.number().nullable(),
  eventAt: z.string(),
  receivedAt: z.string(),
  updatedAt: z.string(),
});
export type VehicleCurrentPosition = z.infer<typeof VehicleCurrentPositionSchema>;

/** location_geojson is always non-null for a real current-position row (the underlying column is NOT NULL) -- a caller with no current position gets no row at all, never a null-location one. */
export function parseVehicleCurrentPosition(row: Record<string, unknown>): VehicleCurrentPosition {
  const location = row.location_geojson as { coordinates: [number, number] };
  return VehicleCurrentPositionSchema.parse({
    vehicleMasterId: row.vehicle_master_id,
    tenantId: row.tenant_id,
    sourceType: row.source_type,
    latitude: location.coordinates[1],
    longitude: location.coordinates[0],
    speedKmh: row.speed_kmh ?? null,
    headingDegrees: row.heading_degrees ?? null,
    eventAt: row.event_at,
    receivedAt: row.received_at,
    updatedAt: row.updated_at,
  });
}

export const CanonicalTelemetryEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  sourceType: TelemetrySourceTypeSchema,
  eventAt: z.string(),
  receivedAt: z.string(),
  latitude: z.number().nullable(),
  longitude: z.number().nullable(),
  speedKmh: z.number().nullable(),
  headingDegrees: z.number().nullable(),
  accuracyMeters: z.number().nullable(),
  appliedToCurrentPosition: z.boolean(),
  rejectionReason: z.string().nullable(),
});
export type CanonicalTelemetryEvent = z.infer<typeof CanonicalTelemetryEventSchema>;

/** location_geojson is nullable here (unlike current position) -- a heartbeat canonical event carries no coordinates at all. */
export function parseCanonicalTelemetryEvent(row: Record<string, unknown>): CanonicalTelemetryEvent {
  const location = row.location_geojson as { coordinates?: [number, number] } | null | undefined;
  return CanonicalTelemetryEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vehicleMasterId: row.vehicle_master_id,
    sourceType: row.source_type,
    eventAt: row.event_at,
    receivedAt: row.received_at,
    latitude: location?.coordinates ? location.coordinates[1] : null,
    longitude: location?.coordinates ? location.coordinates[0] : null,
    speedKmh: row.speed_kmh ?? null,
    headingDegrees: row.heading_degrees ?? null,
    accuracyMeters: row.accuracy_meters ?? null,
    appliedToCurrentPosition: row.applied_to_current_position,
    rejectionReason: row.rejection_reason ?? null,
  });
}

export const VEHICLE_SOURCE_HEALTH_STATUSES = ["healthy", "stale", "offline", "unknown"] as const;
export const VehicleSourceHealthStatusSchema = z.enum(VEHICLE_SOURCE_HEALTH_STATUSES);
export type VehicleSourceHealthStatus = z.infer<typeof VehicleSourceHealthStatusSchema>;

export const VehicleSourceHealthSchema = z.object({
  sourceType: TelemetrySourceTypeSchema,
  lastSeenEventAt: z.string().nullable(),
  lastSeenReceivedAt: z.string().nullable(),
  status: VehicleSourceHealthStatusSchema,
});
export type VehicleSourceHealth = z.infer<typeof VehicleSourceHealthSchema>;

export function parseVehicleSourceHealth(row: Record<string, unknown>): VehicleSourceHealth {
  return VehicleSourceHealthSchema.parse({
    sourceType: row.source_type,
    lastSeenEventAt: row.last_seen_event_at ?? null,
    lastSeenReceivedAt: row.last_seen_received_at ?? null,
    status: row.status,
  });
}

export const VEHICLE_SOURCE_SWITCH_REASONS = ["bootstrap", "higher_priority_source_available", "current_source_stale_fallback"] as const;
export const VehicleSourceSwitchReasonSchema = z.enum(VEHICLE_SOURCE_SWITCH_REASONS);
export type VehicleSourceSwitchReason = z.infer<typeof VehicleSourceSwitchReasonSchema>;

export const VehicleSourceSwitchSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  fromSourceType: TelemetrySourceTypeSchema.nullable(),
  toSourceType: TelemetrySourceTypeSchema,
  reason: VehicleSourceSwitchReasonSchema,
  canonicalTelemetryEventId: z.string().uuid(),
  evidence: z.record(z.string(), z.unknown()),
  switchedAt: z.string(),
});
export type VehicleSourceSwitch = z.infer<typeof VehicleSourceSwitchSchema>;

export function parseVehicleSourceSwitch(row: Record<string, unknown>): VehicleSourceSwitch {
  return VehicleSourceSwitchSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vehicleMasterId: row.vehicle_master_id,
    fromSourceType: row.from_source_type ?? null,
    toSourceType: row.to_source_type,
    reason: row.reason,
    canonicalTelemetryEventId: row.canonical_telemetry_event_id,
    evidence: (row.evidence as Record<string, unknown>) ?? {},
    switchedAt: row.switched_at,
  });
}
