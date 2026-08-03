/**
 * Capacity, Utilization and Tracking Coverage contract (ATW-227, CG-S10-ATW-008).
 * Mirrors
 * supabase/migrations/20260730120000_create_advanced_tms_capacity_utilization.sql's
 * app.vehicle_capacity_reservations shape, the app.reserve_vehicle_capacity/
 * app.consume_vehicle_capacity_reservation/app.release_vehicle_capacity_reservation
 * RPCs, and the app.get_tenant_tracking_coverage/app.get_tenant_tracking_utilization_
 * summary read projections.
 *
 * Capacity and tracking usage are separate dimensions (227_*.md §24) -- this module
 * never lets a subscription/tracking-package limit alter a reservation decision, and
 * never lets a reservation mutate entitlement or source policy.
 */

import { z } from "zod";

export const VEHICLE_CAPACITY_RESERVATION_STATUSES = ["held", "consumed", "released"] as const;
export const VehicleCapacityReservationStatusSchema = z.enum(VEHICLE_CAPACITY_RESERVATION_STATUSES);
export type VehicleCapacityReservationStatus = z.infer<typeof VehicleCapacityReservationStatusSchema>;

export const VehicleCapacityReservationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  vehicleMasterId: z.string().uuid(),
  idempotencyKey: z.string(),
  requestedWeightKg: z.coerce.number().nullable(),
  requestedVolumeCbm: z.coerce.number().nullable(),
  windowStart: z.string(),
  windowEnd: z.string(),
  status: VehicleCapacityReservationStatusSchema,
  releasedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VehicleCapacityReservation = z.infer<typeof VehicleCapacityReservationSchema>;

export function parseVehicleCapacityReservation(row: Record<string, unknown>): VehicleCapacityReservation {
  return VehicleCapacityReservationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegId: row.shipment_leg_id,
    vehicleMasterId: row.vehicle_master_id,
    idempotencyKey: row.idempotency_key,
    requestedWeightKg: row.requested_weight_kg ?? null,
    requestedVolumeCbm: row.requested_volume_cbm ?? null,
    windowStart: row.window_start,
    windowEnd: row.window_end,
    status: row.status,
    releasedReason: row.released_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const TRACKING_COVERAGE_SOURCE_CLASSES = ["none", "mobile_only", "direct_device_only", "third_party_only", "hybrid"] as const;
export const TrackingCoverageSourceClassSchema = z.enum(TRACKING_COVERAGE_SOURCE_CLASSES);
export type TrackingCoverageSourceClass = z.infer<typeof TrackingCoverageSourceClassSchema>;

export const TRACKING_COVERAGE_STATUSES = ["tracked", "stale", "offline", "not_tracked"] as const;
export const TrackingCoverageStatusSchema = z.enum(TRACKING_COVERAGE_STATUSES);
export type TrackingCoverageStatus = z.infer<typeof TrackingCoverageStatusSchema>;

export const TenantTrackingCoverageRowSchema = z.object({
  vehicleMasterId: z.string().uuid(),
  vehicleCode: z.string(),
  vehicleName: z.string(),
  sourceClass: TrackingCoverageSourceClassSchema,
  coverageStatus: TrackingCoverageStatusSchema,
  authoritativeSourceType: z.enum(["driver_mobile", "direct_device", "third_party_platform"]).nullable(),
  lastPositionAt: z.string().nullable(),
  hasActiveProviderMapping: z.boolean(),
  capacityWeightKg: z.coerce.number().nullable(),
  capacityVolumeCbm: z.coerce.number().nullable(),
  reservedWeightKg: z.coerce.number(),
  reservedVolumeCbm: z.coerce.number(),
});
export type TenantTrackingCoverageRow = z.infer<typeof TenantTrackingCoverageRowSchema>;

export function parseTenantTrackingCoverageRow(row: Record<string, unknown>): TenantTrackingCoverageRow {
  return TenantTrackingCoverageRowSchema.parse({
    vehicleMasterId: row.vehicle_master_id,
    vehicleCode: row.vehicle_code,
    vehicleName: row.vehicle_name,
    sourceClass: row.source_class,
    coverageStatus: row.coverage_status,
    authoritativeSourceType: row.authoritative_source_type ?? null,
    lastPositionAt: row.last_position_at ?? null,
    hasActiveProviderMapping: row.has_active_provider_mapping,
    capacityWeightKg: row.capacity_weight_kg ?? null,
    capacityVolumeCbm: row.capacity_volume_cbm ?? null,
    reservedWeightKg: row.reserved_weight_kg ?? 0,
    reservedVolumeCbm: row.reserved_volume_cbm ?? 0,
  });
}

export const TenantTrackingUtilizationSummarySchema = z.object({
  trackingEnabled: z.boolean(),
  packageCode: z.string().nullable(),
  maxTrackedVehicles: z.number().int().nullable(),
  maxMobileSessions: z.number().int().nullable(),
  totalActiveVehicleCount: z.number().int(),
  trackedVehicleCount: z.number().int(),
  staleVehicleCount: z.number().int(),
  offlineVehicleCount: z.number().int(),
  notTrackedVehicleCount: z.number().int(),
  trackedVehicleLimitRemaining: z.number().int().nullable(),
  deviceTotalCount: z.number().int(),
  deviceActiveCount: z.number().int(),
  mobileSessionActiveCount: z.number().int(),
  untrackedRequiredLegCount: z.number().int(),
});
export type TenantTrackingUtilizationSummary = z.infer<typeof TenantTrackingUtilizationSummarySchema>;

export function parseTenantTrackingUtilizationSummary(row: Record<string, unknown>): TenantTrackingUtilizationSummary {
  return TenantTrackingUtilizationSummarySchema.parse({
    trackingEnabled: row.tracking_enabled,
    packageCode: row.package_code ?? null,
    maxTrackedVehicles: row.max_tracked_vehicles ?? null,
    maxMobileSessions: row.max_mobile_sessions ?? null,
    totalActiveVehicleCount: row.total_active_vehicle_count,
    trackedVehicleCount: row.tracked_vehicle_count,
    staleVehicleCount: row.stale_vehicle_count,
    offlineVehicleCount: row.offline_vehicle_count,
    notTrackedVehicleCount: row.not_tracked_vehicle_count,
    trackedVehicleLimitRemaining: row.tracked_vehicle_limit_remaining ?? null,
    deviceTotalCount: row.device_total_count,
    deviceActiveCount: row.device_active_count,
    mobileSessionActiveCount: row.mobile_session_active_count,
    untrackedRequiredLegCount: row.untracked_required_leg_count,
  });
}

// --- Mutation input schemas ---

export const ReserveVehicleCapacityInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  requestedWeightKg: z.number().min(0).nullable(),
  requestedVolumeCbm: z.number().min(0).nullable(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReserveVehicleCapacityInput = z.input<typeof ReserveVehicleCapacityInputSchema>;

export const ConsumeVehicleCapacityReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConsumeVehicleCapacityReservationInput = z.input<typeof ConsumeVehicleCapacityReservationInputSchema>;

export const ReleaseVehicleCapacityReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReleaseVehicleCapacityReservationInput = z.input<typeof ReleaseVehicleCapacityReservationInputSchema>;
