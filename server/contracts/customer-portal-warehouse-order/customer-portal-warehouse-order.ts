/**
 * Customer Portal Warehouse Order and Order Fulfillment Visibility contract
 * (CPL-310, CG-S13-CPL-012, Prompt 310). Mirrors supabase/migrations/
 * 20260801110000_create_customer_portal_warehouse_order_fulfillment_
 * visibility.sql's read-only RPC surface: app.get_customer_portal_outbound_
 * order/app.list_customer_portal_outbound_order_lines/app.list_customer_
 * portal_outbound_orders.
 *
 * Row shapes are byte-identical to server/contracts/customer-inventory-access/
 * customer-inventory-access.ts's own CustomerOutboundOrder/
 * CustomerOutboundOrderLine schemas (the migration's own design decision 3:
 * column-for-column parity with ATW-023) -- duplicated here rather than
 * re-exported/imported, since the two migrations are independent, additive
 * capabilities gated by two different resolvers, matching CPL-309's own
 * identical duplication rationale for customer-portal-inventory.ts.
 */

import { z } from "zod";

/**
 * The three real values app.wms_outbound_orders.status carries (its own
 * wms_outbound_orders_status_check CHECK constraint) -- never a fabricated
 * fourth state. The raw column is returned verbatim by every RPC; friendly
 * customer-facing labels live only at the UI layer
 * (CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS below), mirroring
 * server/contracts/customer-portal-inventory's own on_hand/held/damaged/
 * expired -> label convention.
 */
export const CUSTOMER_WAREHOUSE_ORDER_STATUSES = ["draft", "confirmed", "cancelled"] as const;
export const CustomerWarehouseOrderStatusSchema = z.enum(CUSTOMER_WAREHOUSE_ORDER_STATUSES);
export type CustomerWarehouseOrderStatus = z.infer<typeof CustomerWarehouseOrderStatusSchema>;

/** Customer-visible label for each real status -- presentation only, never persisted or sent to the RPC layer. */
export const CUSTOMER_WAREHOUSE_ORDER_STATUS_LABELS: Record<CustomerWarehouseOrderStatus, string> = {
  draft: "Preparing",
  confirmed: "Confirmed",
  cancelled: "Cancelled",
};

export const CUSTOMER_WAREHOUSE_ORDER_SOURCE_TYPES = ["shipment_order", "manual"] as const;
export const CustomerWarehouseOrderSourceTypeSchema = z.enum(CUSTOMER_WAREHOUSE_ORDER_SOURCE_TYPES);
export type CustomerWarehouseOrderSourceType = z.infer<typeof CustomerWarehouseOrderSourceTypeSchema>;

// --- Row schemas ---

/** app.get_customer_portal_outbound_order / app.list_customer_portal_outbound_orders -- identical column projection. */
export const CustomerWarehouseOrderSchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  outboundNumber: z.string(),
  sourceType: CustomerWarehouseOrderSourceTypeSchema,
  requestedShipDate: z.string().nullable(),
  status: CustomerWarehouseOrderStatusSchema,
  cancelledReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerWarehouseOrder = z.infer<typeof CustomerWarehouseOrderSchema>;

export function parseCustomerWarehouseOrder(row: Record<string, unknown>): CustomerWarehouseOrder {
  return CustomerWarehouseOrderSchema.parse({
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

/** app.list_customer_portal_outbound_order_lines -- excludes `notes` (free-text, potentially staff-internal). */
export const CustomerWarehouseOrderLineSchema = z.object({
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
export type CustomerWarehouseOrderLine = z.infer<typeof CustomerWarehouseOrderLineSchema>;

export function parseCustomerWarehouseOrderLine(row: Record<string, unknown>): CustomerWarehouseOrderLine {
  return CustomerWarehouseOrderLineSchema.parse({
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

// --- Cursor pagination ---

/**
 * The (timestamp, id) keyset pair app.list_customer_portal_outbound_orders
 * accepts -- never OFFSET. Omit both for the first page; pass the last row's
 * own values to advance. `.refine()` rejects a half-supplied cursor
 * (cursorId without cursorUpdatedAt), mirroring server/contracts/
 * customer-portal-inventory's own CustomerPortalInventoryCursorSchema exactly.
 */
export const CustomerWarehouseOrderCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type CustomerWarehouseOrderCursor = z.input<typeof CustomerWarehouseOrderCursorSchema>;
