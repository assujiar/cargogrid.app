/**
 * Shipment Order contract (OPS-169, CG-S8-OPS-003). Mirrors
 * supabase/migrations/20260727100000_create_operations_shipment_order.sql's
 * app.shipment_orders shape and its RPCs.
 *
 * One single-leg, single-mode executable shipment definition per row, always linked
 * to exactly one confirmed Job Order (OPS-168). shipperAccountId is a live canonical
 * FK; consigneeSnapshot/notifyPartySnapshot are structured jsonb (a shipment's
 * consignee may legitimately differ from the Job Order's own billing customer);
 * cargoServiceSnapshot is a verbatim copy of the Job Order's own snapshot.
 */

import { z } from "zod";

/** Broadened at OPS-170 (Shipment Lifecycle) from the original draft/confirmed/cancelled set -- app.shipment_orders_status_check now covers the full canonical lifecycle. */
export const SHIPMENT_ORDER_STATUSES = [
  "draft",
  "confirmed",
  "planned",
  "assigned",
  "dispatched",
  "in_transit",
  "delivered",
  "epod",
  "closed",
  "held",
  "cancelled",
] as const;
export const ShipmentOrderStatusSchema = z.enum(SHIPMENT_ORDER_STATUSES);
export type ShipmentOrderStatus = z.infer<typeof ShipmentOrderStatusSchema>;

export const SHIPMENT_MODES = ["land", "air", "sea"] as const;
export const ShipmentModeSchema = z.enum(SHIPMENT_MODES);
export type ShipmentMode = z.infer<typeof ShipmentModeSchema>;

export const ShipmentOrderSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  shipmentNumber: z.string(),
  idempotencyKey: z.string(),
  status: ShipmentOrderStatusSchema,
  /** OPS-170: set only while status = 'held' -- the one legal resume target app.transition_shipment_order enforces. */
  heldFromStatus: ShipmentOrderStatusSchema.nullable(),
  shipperAccountId: z.string().uuid(),
  consigneeSnapshot: z.record(z.string(), z.unknown()),
  notifyPartySnapshot: z.record(z.string(), z.unknown()).nullable(),
  cargoServiceSnapshot: z.record(z.string(), z.unknown()),
  serviceType: z.string(),
  mode: ShipmentModeSchema,
  origin: z.string(),
  destination: z.string(),
  plannedPickupAt: z.string().nullable(),
  plannedDeliveryAt: z.string().nullable(),
  basisQuantity: z.coerce.number().nullable(),
  basisWeightKg: z.coerce.number().nullable(),
  basisVolumeCbm: z.coerce.number().nullable(),
  allocatedQuantity: z.coerce.number().nullable(),
  allocatedWeightKg: z.coerce.number().nullable(),
  allocatedVolumeCbm: z.coerce.number().nullable(),
  splitReason: z.string().nullable(),
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type ShipmentOrder = z.infer<typeof ShipmentOrderSchema>;

export function parseShipmentOrder(row: Record<string, unknown>): ShipmentOrder {
  return ShipmentOrderSchema.parse({
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
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_job_shipment_allocation_balance's own return row. A null basis dimension means no cap was ever established for it (advisory-only), distinct from a basis of zero. */
export const JobShipmentAllocationBalanceSchema = z.object({
  basisQuantity: z.coerce.number().nullable(),
  basisWeightKg: z.coerce.number().nullable(),
  basisVolumeCbm: z.coerce.number().nullable(),
  allocatedQuantity: z.coerce.number(),
  allocatedWeightKg: z.coerce.number(),
  allocatedVolumeCbm: z.coerce.number(),
  remainingQuantity: z.coerce.number().nullable(),
  remainingWeightKg: z.coerce.number().nullable(),
  remainingVolumeCbm: z.coerce.number().nullable(),
});
export type JobShipmentAllocationBalance = z.infer<typeof JobShipmentAllocationBalanceSchema>;

export function parseJobShipmentAllocationBalance(row: Record<string, unknown>): JobShipmentAllocationBalance {
  return JobShipmentAllocationBalanceSchema.parse({
    basisQuantity: row.basis_quantity ?? null,
    basisWeightKg: row.basis_weight_kg ?? null,
    basisVolumeCbm: row.basis_volume_cbm ?? null,
    allocatedQuantity: row.allocated_quantity,
    allocatedWeightKg: row.allocated_weight_kg,
    allocatedVolumeCbm: row.allocated_volume_cbm,
    remainingQuantity: row.remaining_quantity ?? null,
    remainingWeightKg: row.remaining_weight_kg ?? null,
    remainingVolumeCbm: row.remaining_volume_cbm ?? null,
  });
}

export const GetJobShipmentAllocationBalanceInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetJobShipmentAllocationBalanceInput = z.input<typeof GetJobShipmentAllocationBalanceInputSchema>;

export const CreateShipmentOrderFromJobInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  consignee: z.record(z.string(), z.unknown()).nullable().default(null),
  notifyParty: z.record(z.string(), z.unknown()).nullable().default(null),
  serviceType: z.string().min(1),
  mode: ShipmentModeSchema,
  origin: z.string().min(1),
  destination: z.string().min(1),
  plannedPickupAt: z.string().nullable().default(null),
  plannedDeliveryAt: z.string().nullable().default(null),
  allocatedQuantity: z.number().nullable().default(null),
  allocatedWeightKg: z.number().nullable().default(null),
  allocatedVolumeCbm: z.number().nullable().default(null),
  basisQuantity: z.number().nullable().default(null),
  basisWeightKg: z.number().nullable().default(null),
  basisVolumeCbm: z.number().nullable().default(null),
  splitReason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateShipmentOrderFromJobInput = z.input<typeof CreateShipmentOrderFromJobInputSchema>;

export const ConfirmShipmentOrderInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConfirmShipmentOrderInput = z.input<typeof ConfirmShipmentOrderInputSchema>;

export const CancelShipmentOrderInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelShipmentOrderInput = z.input<typeof CancelShipmentOrderInputSchema>;
