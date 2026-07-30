/**
 * Advanced Dispatch Board contract (ATW-222, CG-S10-ATW-003). Mirrors
 * supabase/migrations/20260729300000_create_advanced_tms_dispatch_board.sql's
 * app.dispatch_board_queue view shape.
 *
 * Extends OPS-175's own assigned-only ready queue into a wider assigned/dispatched/
 * in_transit operational window, with a canonical tracking-health projection.
 * Tracking columns are honest and feature-gated (not_tracked/unknown/false/not
 * entitled) until ATW-226 ships a real telemetry source -- never a fabricated live
 * position.
 */

import { z } from "zod";
import { ShipmentOrderSchema } from "../shipment-order/shipment-order.ts";
import { DispatchBlockerSchema } from "../basic-dispatch/basic-dispatch.ts";

export const TRACKING_STATUSES = ["not_tracked", "tracked", "stale", "degraded", "conflict"] as const;
export const TrackingStatusSchema = z.enum(TRACKING_STATUSES);
export type TrackingStatus = z.infer<typeof TrackingStatusSchema>;

export const AUTHORITATIVE_SOURCE_TYPES = ["driver_mobile", "direct_device", "third_party_platform", "hybrid"] as const;
export const AuthoritativeSourceTypeSchema = z.enum(AUTHORITATIVE_SOURCE_TYPES).nullable();
export type AuthoritativeSourceType = z.infer<typeof AuthoritativeSourceTypeSchema>;

export const FRESHNESS_STATUSES = ["fresh", "stale", "unknown"] as const;
export const FreshnessStatusSchema = z.enum(FRESHNESS_STATUSES);
export type FreshnessStatus = z.infer<typeof FreshnessStatusSchema>;

/** app.dispatch_board_queue row -- every app.shipment_orders column plus readiness, active-assignment, and tracking-health projections. */
export const DispatchBoardRowSchema = ShipmentOrderSchema.extend({
  isReady: z.boolean().nullable(),
  blockers: z.array(DispatchBlockerSchema).nullable(),
  hasActiveAssignment: z.boolean(),
  trackingStatus: TrackingStatusSchema,
  authoritativeSourceType: AuthoritativeSourceTypeSchema,
  lastPositionAt: z.string().nullable(),
  freshnessStatus: FreshnessStatusSchema,
  accuracyMeters: z.coerce.number().nullable(),
  fallbackActive: z.boolean(),
  trackingEntitled: z.boolean(),
  trackingExceptionCount: z.number().int().nonnegative(),
});
export type DispatchBoardRow = z.infer<typeof DispatchBoardRowSchema>;

export function parseDispatchBoardRow(row: Record<string, unknown>): DispatchBoardRow {
  return DispatchBoardRowSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobOrderId: row.job_order_id,
    shipmentNumber: row.shipment_number,
    idempotencyKey: row.idempotency_key,
    status: row.status,
    heldFromStatus: row.held_from_status ?? null,
    shipperAccountId: row.shipper_account_id,
    consigneeSnapshot: row.consignee_snapshot,
    notifyPartySnapshot: row.notify_party_snapshot ?? null,
    cargoServiceSnapshot: row.cargo_service_snapshot,
    serviceType: row.service_type,
    mode: row.mode,
    origin: row.origin,
    destination: row.destination,
    plannedPickupAt: row.planned_pickup_at ?? null,
    plannedDeliveryAt: row.planned_delivery_at ?? null,
    basisQuantity: row.basis_quantity ?? null,
    basisWeightKg: row.basis_weight_kg ?? null,
    basisVolumeCbm: row.basis_volume_cbm ?? null,
    allocatedQuantity: row.allocated_quantity ?? null,
    allocatedWeightKg: row.allocated_weight_kg ?? null,
    allocatedVolumeCbm: row.allocated_volume_cbm ?? null,
    splitReason: row.split_reason ?? null,
    ownerUserId: row.owner_user_id ?? null,
    orgUnitId: row.org_unit_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    legNetworkStatus: row.leg_network_status ?? null,
    isReady: row.is_ready ?? null,
    blockers: row.blockers ?? null,
    hasActiveAssignment: row.has_active_assignment,
    trackingStatus: row.tracking_status,
    authoritativeSourceType: row.authoritative_source_type ?? null,
    lastPositionAt: row.last_position_at ?? null,
    freshnessStatus: row.freshness_status,
    accuracyMeters: row.accuracy_meters ?? null,
    fallbackActive: row.fallback_active,
    trackingEntitled: row.tracking_entitled,
    trackingExceptionCount: row.tracking_exception_count,
  });
}
