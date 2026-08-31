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

// ---------------------------------------------------------------------------
// Inbound half (ISS-2026-120). Kept in this file rather than a new one: the two
// halves are one capability to a reader and to the page that renders them, and
// splitting them would make the asymmetries below harder to see, not easier.
//
// Three things genuinely differ from the outbound schemas above, and each is
// forced by app.wms_inbound_orders' own shape rather than chosen -- see the
// migration header for the full reasoning.
// ---------------------------------------------------------------------------

/**
 * Four real values, not three: `scheduled` has no outbound counterpart. Taken
 * from wms_inbound_orders_status_check directly, never invented.
 */
export const CUSTOMER_INBOUND_ORDER_STATUSES = ["draft", "scheduled", "confirmed", "cancelled"] as const;
export const CustomerInboundOrderStatusSchema = z.enum(CUSTOMER_INBOUND_ORDER_STATUSES);
export type CustomerInboundOrderStatus = z.infer<typeof CustomerInboundOrderStatusSchema>;

/** Customer-visible label per real status -- presentation only, never persisted or sent to the RPC layer. */
export const CUSTOMER_INBOUND_ORDER_STATUS_LABELS: Record<CustomerInboundOrderStatus, string> = {
  draft: "Preparing",
  scheduled: "Appointment booked",
  confirmed: "Confirmed",
  cancelled: "Cancelled",
};

/** Three real values, not two: inbound orders can also originate from an import. */
export const CUSTOMER_INBOUND_ORDER_SOURCE_TYPES = ["shipment_order", "manual", "import"] as const;
export const CustomerInboundOrderSourceTypeSchema = z.enum(CUSTOMER_INBOUND_ORDER_SOURCE_TYPES);
export type CustomerInboundOrderSourceType = z.infer<typeof CustomerInboundOrderSourceTypeSchema>;

/** app.get_customer_portal_inbound_order / app.list_customer_portal_inbound_orders -- identical column projection. */
export const CustomerInboundOrderSchema = z.object({
  id: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  inboundNumber: z.string(),
  sourceType: CustomerInboundOrderSourceTypeSchema,
  expectedDate: z.string().nullable(),
  appointmentWindowStart: z.string().nullable(),
  appointmentWindowEnd: z.string().nullable(),
  status: CustomerInboundOrderStatusSchema,
  cancelledReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CustomerInboundOrder = z.infer<typeof CustomerInboundOrderSchema>;

export function parseCustomerInboundOrder(row: Record<string, unknown>): CustomerInboundOrder {
  return CustomerInboundOrderSchema.parse({
    id: row.id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    inboundNumber: row.inbound_number,
    sourceType: row.source_type,
    expectedDate: row.expected_date ?? null,
    appointmentWindowStart: row.appointment_window_start ?? null,
    appointmentWindowEnd: row.appointment_window_end ?? null,
    status: row.status,
    cancelledReason: row.cancelled_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.list_customer_portal_inbound_order_lines -- excludes `notes` (free-text, potentially staff-internal), exactly as the outbound line schema does. */
export const CustomerInboundOrderLineSchema = z.object({
  id: z.string().uuid(),
  inboundOrderId: z.string().uuid(),
  lineNumber: z.number().int(),
  itemMasterId: z.string().uuid(),
  expectedUomCode: z.string(),
  expectedQuantity: z.coerce.number(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  recordVersion: z.number().int().positive(),
  updatedAt: z.string(),
});
export type CustomerInboundOrderLine = z.infer<typeof CustomerInboundOrderLineSchema>;

export function parseCustomerInboundOrderLine(row: Record<string, unknown>): CustomerInboundOrderLine {
  return CustomerInboundOrderLineSchema.parse({
    id: row.id,
    inboundOrderId: row.inbound_order_id,
    lineNumber: row.line_number,
    itemMasterId: row.item_master_id,
    expectedUomCode: row.expected_uom_code,
    expectedQuantity: row.expected_quantity,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    recordVersion: row.record_version,
    updatedAt: row.updated_at,
  });
}
