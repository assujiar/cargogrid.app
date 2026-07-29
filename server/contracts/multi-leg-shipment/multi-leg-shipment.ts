/**
 * Multi-Leg and Multimodal Shipment contract (ATW-221, CG-S10-ATW-002). Mirrors
 * supabase/migrations/20260729290000_create_advanced_tms_multi_leg_shipment.sql's
 * app.shipment_legs / app.shipment_leg_stops / app.shipment_leg_cargo_allocations /
 * app.shipment_leg_custody_events shapes and their RPCs.
 *
 * A leg is never an independent shipment -- it always belongs to exactly one
 * Shipment Order (the canonical root, OPS-169). leg_network_status lives on
 * app.shipment_orders itself (a nullable additive projection, never a second
 * lifecycle) and is exposed here as part of getShipmentLegNetwork's own composed
 * result rather than duplicated into the Shipment Order contract.
 */

import { z } from "zod";

export const SHIPMENT_LEG_MODES = ["land", "air", "sea"] as const;
export const ShipmentLegModeSchema = z.enum(SHIPMENT_LEG_MODES);
export type ShipmentLegMode = z.infer<typeof ShipmentLegModeSchema>;

export const SHIPMENT_LEG_STATUSES = ["planned", "dispatched", "in_transit", "arrived", "completed", "cancelled"] as const;
export const ShipmentLegStatusSchema = z.enum(SHIPMENT_LEG_STATUSES);
export type ShipmentLegStatus = z.infer<typeof ShipmentLegStatusSchema>;

export const SHIPMENT_LEG_STOP_TYPES = ["pickup", "transfer", "delivery"] as const;
export const ShipmentLegStopTypeSchema = z.enum(SHIPMENT_LEG_STOP_TYPES);
export type ShipmentLegStopType = z.infer<typeof ShipmentLegStopTypeSchema>;

export const SHIPMENT_LEG_STOP_STATUSES = ["pending", "arrived", "departed", "skipped"] as const;
export const ShipmentLegStopStatusSchema = z.enum(SHIPMENT_LEG_STOP_STATUSES);
export type ShipmentLegStopStatus = z.infer<typeof ShipmentLegStopStatusSchema>;

export const SHIPMENT_LEG_CUSTODY_EVENT_TYPES = ["custody_transfer", "handoff_confirmed"] as const;
export const ShipmentLegCustodyEventTypeSchema = z.enum(SHIPMENT_LEG_CUSTODY_EVENT_TYPES);
export type ShipmentLegCustodyEventType = z.infer<typeof ShipmentLegCustodyEventTypeSchema>;

export const LEG_NETWORK_STATUSES = ["draft", "confirmed"] as const;
export const LegNetworkStatusSchema = z.enum(LEG_NETWORK_STATUSES).nullable();
export type LegNetworkStatus = z.infer<typeof LegNetworkStatusSchema>;

export const LEG_NETWORK_AGGREGATE_STATES = ["not_started", "blocked", "in_progress", "completed"] as const;
export const LegNetworkAggregateStateSchema = z.enum(LEG_NETWORK_AGGREGATE_STATES);
export type LegNetworkAggregateState = z.infer<typeof LegNetworkAggregateStateSchema>;

export const ShipmentLegSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  sequenceNo: z.number().int().positive(),
  idempotencyKey: z.string(),
  mode: ShipmentLegModeSchema,
  legStatus: ShipmentLegStatusSchema,
  isLegacyCompat: z.boolean(),
  carrierMasterId: z.string().uuid().nullable(),
  plannedDepartureAt: z.string().nullable(),
  plannedArrivalAt: z.string().nullable(),
  actualDepartureAt: z.string().nullable(),
  actualArrivalAt: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentLeg = z.infer<typeof ShipmentLegSchema>;

export function parseShipmentLeg(row: Record<string, unknown>): ShipmentLeg {
  return ShipmentLegSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    sequenceNo: row.sequence_no,
    idempotencyKey: row.idempotency_key,
    mode: row.mode,
    legStatus: row.leg_status,
    isLegacyCompat: row.is_legacy_compat,
    carrierMasterId: row.carrier_master_id ?? null,
    plannedDepartureAt: row.planned_departure_at ?? null,
    plannedArrivalAt: row.planned_arrival_at ?? null,
    actualDepartureAt: row.actual_departure_at ?? null,
    actualArrivalAt: row.actual_arrival_at ?? null,
    ownerUserId: row.owner_user_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentLegStopSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  stopSequence: z.number().int().positive(),
  stopType: ShipmentLegStopTypeSchema,
  locationName: z.string(),
  address: z.string().nullable(),
  longitude: z.number().nullable(),
  latitude: z.number().nullable(),
  plannedAt: z.string().nullable(),
  actualAt: z.string().nullable(),
  stopStatus: ShipmentLegStopStatusSchema,
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentLegStop = z.infer<typeof ShipmentLegStopSchema>;

function extractGeojsonPoint(geojson: unknown): { longitude: number | null; latitude: number | null } {
  if (!geojson || typeof geojson !== "object") {
    return { longitude: null, latitude: null };
  }
  const coordinates = (geojson as { coordinates?: unknown }).coordinates;
  if (!Array.isArray(coordinates) || coordinates.length !== 2) {
    return { longitude: null, latitude: null };
  }
  return { longitude: Number(coordinates[0]), latitude: Number(coordinates[1]) };
}

export function parseShipmentLegStop(row: Record<string, unknown>): ShipmentLegStop {
  const { longitude, latitude } = extractGeojsonPoint(row.location_geojson);
  return ShipmentLegStopSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegId: row.shipment_leg_id,
    stopSequence: row.stop_sequence,
    stopType: row.stop_type,
    locationName: row.location_name,
    address: row.address ?? null,
    longitude,
    latitude,
    plannedAt: row.planned_at ?? null,
    actualAt: row.actual_at ?? null,
    stopStatus: row.stop_status,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentLegCargoAllocationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  allocatedQuantity: z.coerce.number().nullable(),
  allocatedWeightKg: z.coerce.number().nullable(),
  allocatedVolumeCbm: z.coerce.number().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentLegCargoAllocation = z.infer<typeof ShipmentLegCargoAllocationSchema>;

export function parseShipmentLegCargoAllocation(row: Record<string, unknown>): ShipmentLegCargoAllocation {
  return ShipmentLegCargoAllocationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegId: row.shipment_leg_id,
    allocatedQuantity: row.allocated_quantity ?? null,
    allocatedWeightKg: row.allocated_weight_kg ?? null,
    allocatedVolumeCbm: row.allocated_volume_cbm ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ShipmentLegCustodyEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentLegId: z.string().uuid(),
  sequenceNo: z.number().int().positive(),
  eventType: ShipmentLegCustodyEventTypeSchema,
  fromPartySnapshot: z.record(z.string(), z.unknown()).nullable(),
  toPartySnapshot: z.record(z.string(), z.unknown()),
  occurredAt: z.string(),
  evidence: z.record(z.string(), z.unknown()).nullable(),
  recordedBy: z.string().nullable(),
  createdAt: z.string(),
});
export type ShipmentLegCustodyEvent = z.infer<typeof ShipmentLegCustodyEventSchema>;

export function parseShipmentLegCustodyEvent(row: Record<string, unknown>): ShipmentLegCustodyEvent {
  return ShipmentLegCustodyEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentLegId: row.shipment_leg_id,
    sequenceNo: row.sequence_no,
    eventType: row.event_type,
    fromPartySnapshot: row.from_party_snapshot ?? null,
    toPartySnapshot: row.to_party_snapshot,
    occurredAt: row.occurred_at,
    evidence: row.evidence ?? null,
    recordedBy: row.recorded_by ?? null,
    createdAt: row.created_at,
  });
}

// --- Mutation input schemas ---

export const AddShipmentLegInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  sequenceNo: z.number().int().positive(),
  mode: ShipmentLegModeSchema,
  carrierMasterId: z.string().uuid().nullable(),
  plannedDepartureAt: z.string().nullable(),
  plannedArrivalAt: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddShipmentLegInput = z.input<typeof AddShipmentLegInputSchema>;

export const CancelShipmentLegInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelShipmentLegInput = z.input<typeof CancelShipmentLegInputSchema>;

export const AddShipmentLegStopInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  stopSequence: z.number().int().positive(),
  stopType: ShipmentLegStopTypeSchema,
  locationName: z.string().min(1),
  address: z.string().nullable(),
  longitude: z.number().min(-180).max(180).nullable(),
  latitude: z.number().min(-90).max(90).nullable(),
  plannedAt: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddShipmentLegStopInput = z.input<typeof AddShipmentLegStopInputSchema>;

export const AllocateShipmentLegCargoInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  allocatedQuantity: z.number().nullable(),
  allocatedWeightKg: z.number().nullable(),
  allocatedVolumeCbm: z.number().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AllocateShipmentLegCargoInput = z.input<typeof AllocateShipmentLegCargoInputSchema>;

export const ConfirmShipmentLegNetworkInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConfirmShipmentLegNetworkInput = z.input<typeof ConfirmShipmentLegNetworkInputSchema>;

export const TransitionShipmentLegInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  toStatus: ShipmentLegStatusSchema,
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type TransitionShipmentLegInput = z.input<typeof TransitionShipmentLegInputSchema>;

export const RecordShipmentLegCustodyEventInputSchema = z.object({
  shipmentLegId: z.string().uuid(),
  eventType: ShipmentLegCustodyEventTypeSchema,
  fromPartySnapshot: z.record(z.string(), z.unknown()).nullable(),
  toPartySnapshot: z.record(z.string(), z.unknown()),
  occurredAt: z.string(),
  evidence: z.record(z.string(), z.unknown()).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordShipmentLegCustodyEventInput = z.input<typeof RecordShipmentLegCustodyEventInputSchema>;

export const MigrateLegacyShipmentToLegNetworkInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type MigrateLegacyShipmentToLegNetworkInput = z.input<typeof MigrateLegacyShipmentToLegNetworkInputSchema>;
