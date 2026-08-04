/**
 * Customer Inventory Access contract (ATW-023, CG-S10-ATW-023, Prompt 242). Mirrors
 * supabase/migrations/20260730310000_create_advanced_tms_customer_inventory_access.sql's
 * read-only RPC surface: app.get_customer_inventory_balance/app.list_customer_
 * inventory_balances/app.list_customer_lot_identities/app.list_customer_serial_
 * identities/app.get_customer_outbound_order/app.list_customer_outbound_order_lines/
 * app.list_customer_outbound_orders/app.list_customer_inventory_movement_summary/
 * app.export_customer_inventory_snapshot/app.list_customer_warehouse_eligibility.
 *
 * Every row schema below is the exact, narrower-than-`select *` column projection the
 * migration's own header discloses per RPC -- never the full underlying table shape.
 */

import { z } from "zod";

export const CUSTOMER_INVENTORY_BALANCE_STATUSES = ["on_hand", "held", "damaged", "expired"] as const;
export const CustomerInventoryBalanceStatusSchema = z.enum(CUSTOMER_INVENTORY_BALANCE_STATUSES);
export type CustomerInventoryBalanceStatus = z.infer<typeof CustomerInventoryBalanceStatusSchema>;

export const CUSTOMER_IDENTITY_STATUSES = ["active", "held", "quarantined", "expired", "consumed"] as const;
export const CustomerIdentityStatusSchema = z.enum(CUSTOMER_IDENTITY_STATUSES);
export type CustomerIdentityStatus = z.infer<typeof CustomerIdentityStatusSchema>;

export const CUSTOMER_OUTBOUND_ORDER_STATUSES = ["draft", "confirmed", "cancelled"] as const;
export const CustomerOutboundOrderStatusSchema = z.enum(CUSTOMER_OUTBOUND_ORDER_STATUSES);
export type CustomerOutboundOrderStatus = z.infer<typeof CustomerOutboundOrderStatusSchema>;

export const CUSTOMER_WAREHOUSE_ELIGIBILITY_STATUSES = ["active", "revoked"] as const;
export const CustomerWarehouseEligibilityStatusSchema = z.enum(CUSTOMER_WAREHOUSE_ELIGIBILITY_STATUSES);
export type CustomerWarehouseEligibilityStatus = z.infer<typeof CustomerWarehouseEligibilityStatusSchema>;

// --- Row schemas ---

/** app.get_customer_inventory_balance / app.list_customer_inventory_balances / app.export_customer_inventory_snapshot -- identical column projection. */
export const CustomerInventoryBalanceSchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  locationId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  status: CustomerInventoryBalanceStatusSchema,
  onHand: z.coerce.number(),
  reserved: z.coerce.number(),
  held: z.coerce.number(),
  available: z.coerce.number(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerInventoryBalance = z.infer<typeof CustomerInventoryBalanceSchema>;

export function parseCustomerInventoryBalance(row: Record<string, unknown>): CustomerInventoryBalance {
  return CustomerInventoryBalanceSchema.parse({
    id: row.id,
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

/** app.list_customer_lot_identities -- excludes parent_lot_id/source_type/source_id/created_by (migration design note 10). */
export const CustomerLotIdentitySchema = z.object({
  id: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  lotNumber: z.string(),
  manufactureDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  status: CustomerIdentityStatusSchema,
  holdReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerLotIdentity = z.infer<typeof CustomerLotIdentitySchema>;

export function parseCustomerLotIdentity(row: Record<string, unknown>): CustomerLotIdentity {
  return CustomerLotIdentitySchema.parse({
    id: row.id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    lotNumber: row.lot_number,
    manufactureDate: row.manufacture_date ?? null,
    expiryDate: row.expiry_date ?? null,
    status: row.status,
    holdReason: row.hold_reason ?? null,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

/** app.list_customer_serial_identities -- excludes source_type/source_id/idempotency_key/created_by (migration design note 10). */
export const CustomerSerialIdentitySchema = z.object({
  id: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  serialNumber: z.string(),
  lotNumber: z.string().nullable(),
  manufactureDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  status: CustomerIdentityStatusSchema,
  holdReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerSerialIdentity = z.infer<typeof CustomerSerialIdentitySchema>;

export function parseCustomerSerialIdentity(row: Record<string, unknown>): CustomerSerialIdentity {
  return CustomerSerialIdentitySchema.parse({
    id: row.id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    serialNumber: row.serial_number,
    lotNumber: row.lot_number ?? null,
    manufactureDate: row.manufacture_date ?? null,
    expiryDate: row.expiry_date ?? null,
    status: row.status,
    holdReason: row.hold_reason ?? null,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

/** app.get_customer_outbound_order / app.list_customer_outbound_orders -- excludes source_shipment_order_id/source_reason/idempotency_key/created_by (migration design note 10). */
export const CustomerOutboundOrderSchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  outboundNumber: z.string(),
  sourceType: z.enum(["shipment_order", "manual"]),
  requestedShipDate: z.string().nullable(),
  status: CustomerOutboundOrderStatusSchema,
  cancelledReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerOutboundOrder = z.infer<typeof CustomerOutboundOrderSchema>;

export function parseCustomerOutboundOrder(row: Record<string, unknown>): CustomerOutboundOrder {
  return CustomerOutboundOrderSchema.parse({
    id: row.id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    outboundNumber: row.outbound_number,
    sourceType: row.source_type,
    requestedShipDate: row.requested_ship_date ?? null,
    status: row.status,
    cancelledReason: row.cancelled_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.list_customer_outbound_order_lines -- excludes notes (migration design note 10). */
export const CustomerOutboundOrderLineSchema = z.object({
  id: z.string().uuid(),
  outboundOrderId: z.string().uuid(),
  lineNumber: z.number().int(),
  itemMasterId: z.string().uuid(),
  requestedUomCode: z.string(),
  requestedQuantity: z.coerce.number(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerOutboundOrderLine = z.infer<typeof CustomerOutboundOrderLineSchema>;

export function parseCustomerOutboundOrderLine(row: Record<string, unknown>): CustomerOutboundOrderLine {
  return CustomerOutboundOrderLineSchema.parse({
    id: row.id,
    outboundOrderId: row.outbound_order_id,
    lineNumber: row.line_number,
    itemMasterId: row.item_master_id,
    requestedUomCode: row.requested_uom_code,
    requestedQuantity: row.requested_quantity,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}

/** app.list_customer_inventory_movement_summary -- movement_type/occurred_at/item_master_id/warehouse_id/signed_quantity/lot_number/serial_number only, no internal source_type/posted_by (migration design note 10, Prompt 242's own required column list verbatim). */
export const CustomerInventoryMovementSummarySchema = z.object({
  id: z.string().uuid(),
  movementId: z.string().uuid(),
  movementType: z.enum(["receipt", "transfer", "consumption", "adjustment", "opening_balance", "reversal"]),
  occurredAt: z.string(),
  itemMasterId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  signedQuantity: z.coerce.number(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
});
export type CustomerInventoryMovementSummary = z.infer<typeof CustomerInventoryMovementSummarySchema>;

export function parseCustomerInventoryMovementSummary(row: Record<string, unknown>): CustomerInventoryMovementSummary {
  return CustomerInventoryMovementSummarySchema.parse({
    id: row.id,
    movementId: row.movement_id,
    movementType: row.movement_type,
    occurredAt: row.occurred_at,
    itemMasterId: row.item_master_id,
    warehouseId: row.warehouse_id,
    signedQuantity: row.signed_quantity,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
  });
}

/** app.list_customer_warehouse_eligibility -- excludes granted_by (a staff label, migration design note 10); includes revoked_reason (a customer legitimately needs to know why a grant was revoked). */
export const CustomerWarehouseEligibilitySchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  status: CustomerWarehouseEligibilityStatusSchema,
  grantedAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type CustomerWarehouseEligibility = z.infer<typeof CustomerWarehouseEligibilitySchema>;

export function parseCustomerWarehouseEligibility(row: Record<string, unknown>): CustomerWarehouseEligibility {
  return CustomerWarehouseEligibilitySchema.parse({
    id: row.id,
    warehouseId: row.warehouse_id,
    customerAccountId: row.customer_account_id,
    status: row.status,
    grantedAt: row.granted_at,
    revokedAt: row.revoked_at ?? null,
    revokedReason: row.revoked_reason ?? null,
    recordVersion: row.record_version,
  });
}

// --- Cursor pagination ---

/**
 * The (timestamp, id) keyset pair every list RPC in this migration accepts -- never
 * OFFSET (migration design note 7). Omit both for the first page; pass the last
 * row's own values to advance. `.refine()` below rejects a half-supplied cursor
 * (cursorId without cursorUpdatedAt) rather than letting it silently reach the RPC
 * and return an empty page -- the database-level guard (design note 7) is the real
 * enforcement boundary since this schema is not wired into every caller path yet,
 * but a future Step 13 Portal consumer that does call `.parse()`/`.safeParse()` on
 * this schema gets the same clear validation error one layer earlier.
 */
export const CustomerInventoryCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerInventoryCursor = z.input<typeof CustomerInventoryCursorSchema>;

// --- Read input schemas ---

export const ExportCustomerInventorySnapshotInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  warehouseId: z.string().uuid().nullable().optional(),
  itemMasterId: z.string().uuid().nullable().optional(),
  limit: z.number().int().positive().nullable().optional(),
  actorLabel: z.string().nullable().optional(),
});
export type ExportCustomerInventorySnapshotInput = z.input<typeof ExportCustomerInventorySnapshotInputSchema>;
