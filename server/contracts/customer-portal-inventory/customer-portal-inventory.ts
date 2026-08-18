/**
 * Customer Portal Warehouse Inventory Visibility contract (CPL-309,
 * CG-S13-CPL-011, Prompt 309). Mirrors supabase/migrations/
 * 20260801100000_create_customer_portal_warehouse_inventory_visibility.sql's
 * read-only RPC surface: app.get_customer_portal_inventory_balance/app.list_
 * customer_portal_inventory_balances/app.list_customer_portal_warehouse_
 * eligibility.
 *
 * Row shapes are byte-identical to server/contracts/customer-inventory-access/
 * customer-inventory-access.ts's own CustomerInventoryBalance/
 * CustomerWarehouseEligibility schemas (the migration's own design decision 3:
 * projection-for-projection parity with ATW-023) -- duplicated here rather than
 * re-exported/imported, since the two migrations are independent, additive
 * capabilities gated by two different resolvers and this contract module should
 * not create a cross-capability TypeScript coupling neither migration's own SQL
 * has.
 */

import { z } from "zod";

export const CUSTOMER_PORTAL_INVENTORY_BALANCE_STATUSES = ["on_hand", "held", "damaged", "expired"] as const;
export const CustomerPortalInventoryBalanceStatusSchema = z.enum(CUSTOMER_PORTAL_INVENTORY_BALANCE_STATUSES);
export type CustomerPortalInventoryBalanceStatus = z.infer<typeof CustomerPortalInventoryBalanceStatusSchema>;

export const CUSTOMER_PORTAL_WAREHOUSE_ELIGIBILITY_STATUSES = ["active", "revoked"] as const;
export const CustomerPortalWarehouseEligibilityStatusSchema = z.enum(CUSTOMER_PORTAL_WAREHOUSE_ELIGIBILITY_STATUSES);
export type CustomerPortalWarehouseEligibilityStatus = z.infer<typeof CustomerPortalWarehouseEligibilityStatusSchema>;

// --- Row schemas ---

/** app.get_customer_portal_inventory_balance / app.list_customer_portal_inventory_balances -- identical column projection. */
export const CustomerPortalInventoryBalanceSchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  locationId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  status: CustomerPortalInventoryBalanceStatusSchema,
  onHand: z.coerce.number(),
  reserved: z.coerce.number(),
  held: z.coerce.number(),
  available: z.coerce.number(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerPortalInventoryBalance = z.infer<typeof CustomerPortalInventoryBalanceSchema>;

export function parseCustomerPortalInventoryBalance(row: Record<string, unknown>): CustomerPortalInventoryBalance {
  return CustomerPortalInventoryBalanceSchema.parse({
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

/** app.list_customer_portal_warehouse_eligibility -- excludes granted_by (a staff label); includes revoked_reason (a customer legitimately needs to know why a grant was revoked). */
export const CustomerPortalWarehouseEligibilitySchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  status: CustomerPortalWarehouseEligibilityStatusSchema,
  grantedAt: z.string(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type CustomerPortalWarehouseEligibility = z.infer<typeof CustomerPortalWarehouseEligibilitySchema>;

export function parseCustomerPortalWarehouseEligibility(row: Record<string, unknown>): CustomerPortalWarehouseEligibility {
  return CustomerPortalWarehouseEligibilitySchema.parse({
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
 * The (timestamp, id) keyset pair app.list_customer_portal_inventory_balances
 * accepts -- never OFFSET. Omit both for the first page; pass the last row's own
 * values to advance. `.refine()` rejects a half-supplied cursor (cursorId
 * without cursorUpdatedAt), mirroring server/contracts/customer-inventory-access/
 * customer-inventory-access.ts's own CustomerInventoryCursorSchema exactly.
 */
export const CustomerPortalInventoryCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerPortalInventoryCursor = z.input<typeof CustomerPortalInventoryCursorSchema>;
