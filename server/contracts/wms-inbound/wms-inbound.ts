/**
 * WMS Inbound contract (ATW-012, CG-S10-ATW-012, Prompt 231). Mirrors
 * supabase/migrations/20260730180000_create_advanced_tms_wms_inbound.sql's
 * app.wms_inbound_orders/app.wms_inbound_order_lines shapes and their
 * prepare/create/line/schedule/confirm/cancel/read RPCs.
 */

import { z } from "zod";

export const WMS_INBOUND_ORDER_STATUSES = ["draft", "scheduled", "confirmed", "cancelled"] as const;
export const WmsInboundOrderStatusSchema = z.enum(WMS_INBOUND_ORDER_STATUSES);
export type WmsInboundOrderStatus = z.infer<typeof WmsInboundOrderStatusSchema>;

export const WMS_INBOUND_SOURCE_TYPES = ["shipment_order", "manual", "import"] as const;
export const WmsInboundSourceTypeSchema = z.enum(WMS_INBOUND_SOURCE_TYPES);
export type WmsInboundSourceType = z.infer<typeof WmsInboundSourceTypeSchema>;

export const WmsInboundOrderSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  inboundNumber: z.string(),
  sourceType: WmsInboundSourceTypeSchema,
  sourceShipmentOrderId: z.string().uuid().nullable(),
  sourceReason: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
  expectedDate: z.string().nullable(),
  appointmentWindowStart: z.string().nullable(),
  appointmentWindowEnd: z.string().nullable(),
  status: WmsInboundOrderStatusSchema,
  cancelledReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsInboundOrder = z.infer<typeof WmsInboundOrderSchema>;

export function parseWmsInboundOrder(row: Record<string, unknown>): WmsInboundOrder {
  return WmsInboundOrderSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    inboundNumber: row.inbound_number,
    sourceType: row.source_type,
    sourceShipmentOrderId: row.source_shipment_order_id ?? null,
    sourceReason: row.source_reason ?? null,
    idempotencyKey: row.idempotency_key ?? null,
    expectedDate: row.expected_date ?? null,
    appointmentWindowStart: row.appointment_window_start ?? null,
    appointmentWindowEnd: row.appointment_window_end ?? null,
    status: row.status,
    cancelledReason: row.cancelled_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsInboundOrderLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  inboundOrderId: z.string().uuid(),
  lineNumber: z.number().int().positive(),
  itemMasterId: z.string().uuid(),
  expectedUomCode: z.string(),
  expectedQuantity: z.coerce.number(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  notes: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsInboundOrderLine = z.infer<typeof WmsInboundOrderLineSchema>;

export function parseWmsInboundOrderLine(row: Record<string, unknown>): WmsInboundOrderLine {
  return WmsInboundOrderLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    inboundOrderId: row.inbound_order_id,
    lineNumber: row.line_number,
    itemMasterId: row.item_master_id,
    expectedUomCode: row.expected_uom_code,
    expectedQuantity: row.expected_quantity,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    notes: row.notes ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsInboundReadinessSchema = z.object({
  hasLines: z.boolean(),
  warehouseActive: z.boolean(),
  ownerActive: z.boolean(),
  invalidLineCount: z.number().int(),
  ready: z.boolean(),
});
export type WmsInboundReadiness = z.infer<typeof WmsInboundReadinessSchema>;

export function parseWmsInboundReadiness(row: Record<string, unknown>): WmsInboundReadiness {
  return WmsInboundReadinessSchema.parse({
    hasLines: row.has_lines,
    warehouseActive: row.warehouse_active,
    ownerActive: row.owner_active,
    invalidLineCount: row.invalid_line_count,
    ready: row.ready,
  });
}

// --- Mutation input schemas ---

export const PrepareWmsInboundFromShipmentInputSchema = z.object({
  tenantId: z.string().uuid(),
  shipmentOrderId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PrepareWmsInboundFromShipmentInput = z.input<typeof PrepareWmsInboundFromShipmentInputSchema>;

export const CreateManualWmsInboundInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  sourceReason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateManualWmsInboundInput = z.input<typeof CreateManualWmsInboundInputSchema>;

export const AddWmsInboundOrderLineInputSchema = z.object({
  inboundOrderId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  expectedUomCode: z.string().min(1),
  expectedQuantity: z.number().positive(),
  notes: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddWmsInboundOrderLineInput = z.input<typeof AddWmsInboundOrderLineInputSchema>;

export const AddWmsInboundOrderLinesInputSchema = z.object({
  inboundOrderId: z.string().uuid(),
  lines: z
    .array(
      z.object({
        itemMasterId: z.string().uuid(),
        expectedUomCode: z.string().min(1),
        expectedQuantity: z.number().positive(),
        notes: z.string().nullable().optional(),
      }),
    )
    .min(1)
    .max(200),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddWmsInboundOrderLinesInput = z.input<typeof AddWmsInboundOrderLinesInputSchema>;

export const UpdateWmsInboundOrderLineInputSchema = z.object({
  lineId: z.string().uuid(),
  expectedQuantity: z.number().positive(),
  notes: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateWmsInboundOrderLineInput = z.input<typeof UpdateWmsInboundOrderLineInputSchema>;

export const RemoveWmsInboundOrderLineInputSchema = z.object({
  lineId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveWmsInboundOrderLineInput = z.input<typeof RemoveWmsInboundOrderLineInputSchema>;

export const ScheduleWmsInboundAppointmentInputSchema = z.object({
  inboundOrderId: z.string().uuid(),
  windowStart: z.string(),
  windowEnd: z.string(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ScheduleWmsInboundAppointmentInput = z.input<typeof ScheduleWmsInboundAppointmentInputSchema>;

export const ConfirmWmsInboundInputSchema = z.object({
  inboundOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConfirmWmsInboundInput = z.input<typeof ConfirmWmsInboundInputSchema>;

export const CancelWmsInboundInputSchema = z.object({
  inboundOrderId: z.string().uuid(),
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelWmsInboundInput = z.input<typeof CancelWmsInboundInputSchema>;
