/**
 * WMS Outbound Order contract (ATW-016A, CG-S10-ATW-016A, inserted -- no source prompt
 * number, mirrors the ATW-011A insertion precedent). Mirrors
 * supabase/migrations/20260730230000_create_advanced_tms_wms_outbound_order.sql's
 * app.wms_outbound_orders/app.wms_outbound_order_lines shapes and their
 * prepare/create/line/confirm/cancel/read RPCs.
 */

import { z } from "zod";

export const WMS_OUTBOUND_ORDER_STATUSES = ["draft", "confirmed", "cancelled"] as const;
export const WmsOutboundOrderStatusSchema = z.enum(WMS_OUTBOUND_ORDER_STATUSES);
export type WmsOutboundOrderStatus = z.infer<typeof WmsOutboundOrderStatusSchema>;

export const WMS_OUTBOUND_SOURCE_TYPES = ["shipment_order", "manual"] as const;
export const WmsOutboundSourceTypeSchema = z.enum(WMS_OUTBOUND_SOURCE_TYPES);
export type WmsOutboundSourceType = z.infer<typeof WmsOutboundSourceTypeSchema>;

export const WmsOutboundOrderSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  outboundNumber: z.string(),
  sourceType: WmsOutboundSourceTypeSchema,
  sourceShipmentOrderId: z.string().uuid().nullable(),
  sourceReason: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  requestedShipDate: z.string().nullable(),
  status: WmsOutboundOrderStatusSchema,
  cancelledReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsOutboundOrder = z.infer<typeof WmsOutboundOrderSchema>;

export function parseWmsOutboundOrder(row: Record<string, unknown>): WmsOutboundOrder {
  return WmsOutboundOrderSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    outboundNumber: row.outbound_number,
    sourceType: row.source_type,
    sourceShipmentOrderId: row.source_shipment_order_id ?? null,
    sourceReason: row.source_reason ?? null,
    idempotencyKey: row.idempotency_key ?? null,
    requestedShipDate: row.requested_ship_date ?? null,
    status: row.status,
    cancelledReason: row.cancelled_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsOutboundOrderLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  outboundOrderId: z.string().uuid(),
  lineNumber: z.number().int().positive(),
  itemMasterId: z.string().uuid(),
  requestedUomCode: z.string(),
  requestedQuantity: z.coerce.number(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  notes: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsOutboundOrderLine = z.infer<typeof WmsOutboundOrderLineSchema>;

export function parseWmsOutboundOrderLine(row: Record<string, unknown>): WmsOutboundOrderLine {
  return WmsOutboundOrderLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    outboundOrderId: row.outbound_order_id,
    lineNumber: row.line_number,
    itemMasterId: row.item_master_id,
    requestedUomCode: row.requested_uom_code,
    requestedQuantity: row.requested_quantity,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    notes: row.notes ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsOutboundReadinessSchema = z.object({
  hasLines: z.boolean(),
  warehouseActive: z.boolean(),
  ownerActive: z.boolean(),
  sourceShipmentValid: z.boolean(),
  invalidLineCount: z.number().int(),
  ready: z.boolean(),
});
export type WmsOutboundReadiness = z.infer<typeof WmsOutboundReadinessSchema>;

export function parseWmsOutboundReadiness(row: Record<string, unknown>): WmsOutboundReadiness {
  return WmsOutboundReadinessSchema.parse({
    hasLines: row.has_lines,
    warehouseActive: row.warehouse_active,
    ownerActive: row.owner_active,
    sourceShipmentValid: row.source_shipment_valid,
    invalidLineCount: row.invalid_line_count,
    ready: row.ready,
  });
}

// --- Mutation input schemas ---

export const PrepareWmsOutboundFromShipmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PrepareWmsOutboundFromShipmentInput = z.input<typeof PrepareWmsOutboundFromShipmentInputSchema>;

export const CreateManualWmsOutboundOrderInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  sourceReason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  requestedShipDate: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateManualWmsOutboundOrderInput = z.input<typeof CreateManualWmsOutboundOrderInputSchema>;

export const AddWmsOutboundOrderLineInputSchema = z.object({
  outboundOrderId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  requestedUomCode: z.string().min(1),
  requestedQuantity: z.number().positive(),
  notes: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddWmsOutboundOrderLineInput = z.input<typeof AddWmsOutboundOrderLineInputSchema>;

export const AddWmsOutboundOrderLinesInputSchema = z.object({
  outboundOrderId: z.string().uuid(),
  lines: z
    .array(
      z.object({
        itemMasterId: z.string().uuid(),
        requestedUomCode: z.string().min(1),
        requestedQuantity: z.number().positive(),
        notes: z.string().nullable().optional(),
      }),
    )
    .min(1)
    .max(200),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddWmsOutboundOrderLinesInput = z.input<typeof AddWmsOutboundOrderLinesInputSchema>;

export const UpdateWmsOutboundOrderLineInputSchema = z.object({
  lineId: z.string().uuid(),
  requestedQuantity: z.number().positive(),
  notes: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateWmsOutboundOrderLineInput = z.input<typeof UpdateWmsOutboundOrderLineInputSchema>;

export const RemoveWmsOutboundOrderLineInputSchema = z.object({
  lineId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveWmsOutboundOrderLineInput = z.input<typeof RemoveWmsOutboundOrderLineInputSchema>;

export const ConfirmWmsOutboundOrderInputSchema = z.object({
  outboundOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConfirmWmsOutboundOrderInput = z.input<typeof ConfirmWmsOutboundOrderInputSchema>;

export const CancelWmsOutboundOrderInputSchema = z.object({
  outboundOrderId: z.string().uuid(),
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelWmsOutboundOrderInput = z.input<typeof CancelWmsOutboundOrderInputSchema>;
