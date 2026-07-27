/**
 * Basic Dispatch contract (OPS-175, CG-S8-OPS-009). Mirrors
 * supabase/migrations/20260727160000_create_operations_basic_dispatch.sql's
 * app.dispatch_commands/app.dispatch_ready_queue shapes and their RPCs.
 *
 * A permission-safe, deterministic readiness queue plus one validated dispatch
 * command for assigned Shipment Orders -- list/queue only, not a dispatch board or
 * route/load/capacity optimization. Dispatch is a thin, readiness-gated wrapper over
 * OPS-170's own already-shipped `assigned -> dispatched` transition, never a second
 * parallel state machine.
 */

import { z } from "zod";
import { ShipmentOrderSchema } from "../shipment-order/shipment-order.ts";

export const DispatchBlockerSchema = z.object({
  code: z.string(),
  detail: z.unknown().nullable(),
});
export type DispatchBlocker = z.infer<typeof DispatchBlockerSchema>;

export const DispatchReadinessSchema = z.object({
  isReady: z.boolean(),
  blockers: z.array(DispatchBlockerSchema),
});
export type DispatchReadiness = z.infer<typeof DispatchReadinessSchema>;

export function parseDispatchReadiness(row: Record<string, unknown>): DispatchReadiness {
  return DispatchReadinessSchema.parse({
    isReady: row.is_ready,
    blockers: row.blockers,
  });
}

/** app.dispatch_ready_queue row -- every app.shipment_orders column plus the same is_ready/blockers app.evaluate_dispatch_readiness computes. */
export const DispatchReadyQueueRowSchema = ShipmentOrderSchema.extend({
  isReady: z.boolean(),
  blockers: z.array(DispatchBlockerSchema),
});
export type DispatchReadyQueueRow = z.infer<typeof DispatchReadyQueueRowSchema>;

export function parseDispatchReadyQueueRow(row: Record<string, unknown>): DispatchReadyQueueRow {
  return DispatchReadyQueueRowSchema.parse({
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
    isReady: row.is_ready,
    blockers: row.blockers,
  });
}

export const DispatchCommandSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  command: z.literal("dispatch"),
  readinessSnapshot: z.object({
    isReady: z.boolean(),
    blockers: z.array(DispatchBlockerSchema),
  }),
  idempotencyKey: z.string(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  dispatchedAt: z.string(),
  createdAt: z.string(),
});
export type DispatchCommand = z.infer<typeof DispatchCommandSchema>;

/** readiness_snapshot is app.evaluate_dispatch_readiness's own (is_ready, blockers) result, persisted verbatim via to_jsonb at commit time. */
export function parseDispatchCommand(row: Record<string, unknown>): DispatchCommand {
  const snapshot = row.readiness_snapshot as Record<string, unknown>;
  return DispatchCommandSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    shipmentOrderId: row.shipment_order_id,
    command: row.command,
    readinessSnapshot: {
      isReady: snapshot?.is_ready,
      blockers: snapshot?.blockers,
    },
    idempotencyKey: row.idempotency_key,
    actorAuthUserId: row.actor_auth_user_id ?? null,
    actorLabel: row.actor_label ?? null,
    dispatchedAt: row.dispatched_at,
    createdAt: row.created_at,
  });
}

export const GetDispatchReadinessInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetDispatchReadinessInput = z.input<typeof GetDispatchReadinessInputSchema>;

export const DispatchShipmentOrderInputSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DispatchShipmentOrderInput = z.input<typeof DispatchShipmentOrderInputSchema>;

/** Bounded at 50 ids per call (app.bulk_dispatch_shipment_orders' own CHECK). */
export const BulkDispatchShipmentOrdersInputSchema = z.object({
  shipmentOrderIds: z.array(z.string().uuid()).min(1).max(50),
  idempotencyKeyPrefix: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type BulkDispatchShipmentOrdersInput = z.input<typeof BulkDispatchShipmentOrdersInputSchema>;

export const BulkDispatchResultRowSchema = z.object({
  shipmentOrderId: z.string().uuid(),
  success: z.boolean(),
  errorCode: z.string().nullable(),
  errorMessage: z.string().nullable(),
});
export type BulkDispatchResultRow = z.infer<typeof BulkDispatchResultRowSchema>;

export function parseBulkDispatchResultRow(row: Record<string, unknown>): BulkDispatchResultRow {
  return BulkDispatchResultRowSchema.parse({
    shipmentOrderId: row.shipment_order_id,
    success: row.success,
    errorCode: row.error_code ?? null,
    errorMessage: row.error_message ?? null,
  });
}
