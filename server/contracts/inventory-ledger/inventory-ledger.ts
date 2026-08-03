/**
 * Inventory Ledger contract (ATW-015, CG-S10-ATW-015, Prompt 234). Mirrors
 * supabase/migrations/20260730190000_create_advanced_tms_inventory_ledger.sql's
 * app.inventory_movements/app.inventory_movement_lines/app.inventory_balances/
 * app.inventory_reservations shapes and their post/reserve/release/consume/
 * reverse/read RPCs.
 */

import { z } from "zod";

export const INVENTORY_MOVEMENT_TYPES = ["receipt", "transfer", "consumption", "adjustment", "opening_balance", "reversal"] as const;
export const InventoryMovementTypeSchema = z.enum(INVENTORY_MOVEMENT_TYPES);
export type InventoryMovementType = z.infer<typeof InventoryMovementTypeSchema>;

export const INVENTORY_SOURCE_TYPES = ["wms_inbound_order", "reservation", "manual", "opening_balance", "reversal"] as const;
export const InventorySourceTypeSchema = z.enum(INVENTORY_SOURCE_TYPES);
export type InventorySourceType = z.infer<typeof InventorySourceTypeSchema>;

export const INVENTORY_BALANCE_STATUSES = ["on_hand", "held", "damaged", "expired"] as const;
export const InventoryBalanceStatusSchema = z.enum(INVENTORY_BALANCE_STATUSES);
export type InventoryBalanceStatus = z.infer<typeof InventoryBalanceStatusSchema>;

export const INVENTORY_RESERVATION_STATUSES = ["active", "consumed", "released"] as const;
export const InventoryReservationStatusSchema = z.enum(INVENTORY_RESERVATION_STATUSES);
export type InventoryReservationStatus = z.infer<typeof InventoryReservationStatusSchema>;

export const INVENTORY_RESERVATION_SOURCE_TYPES = ["wms_inbound_order", "manual"] as const;
export const InventoryReservationSourceTypeSchema = z.enum(INVENTORY_RESERVATION_SOURCE_TYPES);
export type InventoryReservationSourceType = z.infer<typeof InventoryReservationSourceTypeSchema>;

export const InventoryMovementSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  movementType: InventoryMovementTypeSchema,
  sourceType: InventorySourceTypeSchema,
  sourceId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  correctsMovementId: z.string().uuid().nullable(),
  reason: z.string().nullable(),
  occurredAt: z.string(),
  postedBy: z.string().nullable(),
  createdAt: z.string(),
});
export type InventoryMovement = z.infer<typeof InventoryMovementSchema>;

export function parseInventoryMovement(row: Record<string, unknown>): InventoryMovement {
  return InventoryMovementSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    movementType: row.movement_type,
    sourceType: row.source_type,
    sourceId: row.source_id ?? null,
    idempotencyKey: row.idempotency_key,
    correctsMovementId: row.corrects_movement_id ?? null,
    reason: row.reason ?? null,
    occurredAt: row.occurred_at,
    postedBy: row.posted_by ?? null,
    createdAt: row.created_at,
  });
}

export const InventoryMovementLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  movementId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  locationId: z.string().uuid(),
  uomCode: z.string(),
  signedQuantity: z.coerce.number(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  status: InventoryBalanceStatusSchema,
  createdAt: z.string(),
});
export type InventoryMovementLine = z.infer<typeof InventoryMovementLineSchema>;

export function parseInventoryMovementLine(row: Record<string, unknown>): InventoryMovementLine {
  return InventoryMovementLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    movementId: row.movement_id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    locationId: row.location_id,
    uomCode: row.uom_code,
    signedQuantity: row.signed_quantity,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    expiryDate: row.expiry_date ?? null,
    status: row.status,
    createdAt: row.created_at,
  });
}

export const InventoryBalanceSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  locationId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  status: InventoryBalanceStatusSchema,
  onHand: z.coerce.number(),
  reserved: z.coerce.number(),
  held: z.coerce.number(),
  available: z.coerce.number(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type InventoryBalance = z.infer<typeof InventoryBalanceSchema>;

export function parseInventoryBalance(row: Record<string, unknown>): InventoryBalance {
  return InventoryBalanceSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    locationId: row.location_id,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    status: row.status,
    onHand: row.on_hand,
    reserved: row.reserved,
    held: row.held,
    available: row.available,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

export const InventoryReservationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  balanceId: z.string().uuid(),
  reservedQuantity: z.coerce.number(),
  status: InventoryReservationStatusSchema,
  sourceType: InventoryReservationSourceTypeSchema,
  sourceId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  releasedReason: z.string().nullable(),
  consumedMovementId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type InventoryReservation = z.infer<typeof InventoryReservationSchema>;

export function parseInventoryReservation(row: Record<string, unknown>): InventoryReservation {
  return InventoryReservationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    balanceId: row.balance_id,
    reservedQuantity: row.reserved_quantity,
    status: row.status,
    sourceType: row.source_type,
    sourceId: row.source_id ?? null,
    idempotencyKey: row.idempotency_key,
    releasedReason: row.released_reason ?? null,
    consumedMovementId: row.consumed_movement_id ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// --- Mutation input schemas ---

export const PostInventoryMovementLineInputSchema = z.object({
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  locationId: z.string().uuid(),
  uomCode: z.string().min(1),
  signedQuantity: z.number().refine((value) => value !== 0, "signedQuantity must be non-zero"),
  lotNumber: z.string().nullable().optional(),
  serialNumber: z.string().nullable().optional(),
  expiryDate: z.string().nullable().optional(),
  status: InventoryBalanceStatusSchema.optional(),
});
export type PostInventoryMovementLineInput = z.input<typeof PostInventoryMovementLineInputSchema>;

export const PostInventoryMovementInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  movementType: InventoryMovementTypeSchema,
  sourceType: InventorySourceTypeSchema,
  sourceId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().min(1),
  reason: z.string().nullable().optional(),
  lines: z.array(PostInventoryMovementLineInputSchema).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
  correctsMovementId: z.string().uuid().nullable().optional(),
});
export type PostInventoryMovementInput = z.input<typeof PostInventoryMovementInputSchema>;

export const ReserveInventoryInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  locationId: z.string().uuid(),
  lotNumber: z.string().nullable().optional(),
  serialNumber: z.string().nullable().optional(),
  quantity: z.number().positive(),
  sourceType: InventoryReservationSourceTypeSchema,
  sourceId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReserveInventoryInput = z.input<typeof ReserveInventoryInputSchema>;

export const ReleaseInventoryReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  reason: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReleaseInventoryReservationInput = z.input<typeof ReleaseInventoryReservationInputSchema>;

export const ConsumeInventoryReservationInputSchema = z.object({
  reservationId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConsumeInventoryReservationInput = z.input<typeof ConsumeInventoryReservationInputSchema>;

export const ReverseInventoryMovementInputSchema = z.object({
  movementId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReverseInventoryMovementInput = z.input<typeof ReverseInventoryMovementInputSchema>;
