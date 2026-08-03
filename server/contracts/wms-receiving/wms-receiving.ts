/**
 * WMS Receiving contract (ATW-013, CG-S10-ATW-013, Prompt 232). Mirrors
 * supabase/migrations/20260730200000_create_advanced_tms_wms_receiving.sql's
 * app.wms_receipt_sessions/app.wms_receipt_lines shapes and their
 * start/record-count/approve-overage/commit/complete/cancel/resolve-hold/read RPCs.
 */

import { z } from "zod";

export const WMS_RECEIPT_SESSION_STATUSES = ["in_progress", "completed", "cancelled"] as const;
export const WmsReceiptSessionStatusSchema = z.enum(WMS_RECEIPT_SESSION_STATUSES);
export type WmsReceiptSessionStatus = z.infer<typeof WmsReceiptSessionStatusSchema>;

export const WMS_RECEIPT_LINE_STATUSES = ["pending", "counted", "committed"] as const;
export const WmsReceiptLineStatusSchema = z.enum(WMS_RECEIPT_LINE_STATUSES);
export type WmsReceiptLineStatus = z.infer<typeof WmsReceiptLineStatusSchema>;

export const WMS_RECEIPT_HOLD_RESOLUTIONS = ["release_to_stock", "confirm_damaged"] as const;
export const WmsReceiptHoldResolutionSchema = z.enum(WMS_RECEIPT_HOLD_RESOLUTIONS);
export type WmsReceiptHoldResolution = z.infer<typeof WmsReceiptHoldResolutionSchema>;

export const WmsReceiptSessionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  inboundOrderId: z.string().uuid(),
  receivingLocationId: z.string().uuid(),
  idempotencyKey: z.string(),
  status: WmsReceiptSessionStatusSchema,
  cancelledReason: z.string().nullable(),
  startedBy: z.string().nullable(),
  startedAt: z.string(),
  completedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsReceiptSession = z.infer<typeof WmsReceiptSessionSchema>;

export function parseWmsReceiptSession(row: Record<string, unknown>): WmsReceiptSession {
  return WmsReceiptSessionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    inboundOrderId: row.inbound_order_id,
    receivingLocationId: row.receiving_location_id,
    idempotencyKey: row.idempotency_key,
    status: row.status,
    cancelledReason: row.cancelled_reason ?? null,
    startedBy: row.started_by ?? null,
    startedAt: row.started_at,
    completedAt: row.completed_at ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsReceiptLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  receiptSessionId: z.string().uuid(),
  inboundOrderLineId: z.string().uuid(),
  lineNumber: z.number().int().positive(),
  itemMasterId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  expectedUomCode: z.string(),
  expectedQuantity: z.coerce.number(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  countedUomCode: z.string().nullable(),
  countedQuantity: z.coerce.number(),
  acceptedQuantity: z.coerce.number(),
  damagedQuantity: z.coerce.number(),
  heldQuantity: z.coerce.number(),
  rejectedQuantity: z.coerce.number(),
  overQuantity: z.coerce.number(),
  shortQuantity: z.coerce.number(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  conditionNotes: z.string().nullable(),
  status: WmsReceiptLineStatusSchema,
  overApproved: z.boolean(),
  overApprovedReason: z.string().nullable(),
  overApprovedBy: z.string().nullable(),
  overApprovedAt: z.string().nullable(),
  holdResolved: z.boolean(),
  holdResolution: WmsReceiptHoldResolutionSchema.nullable(),
  holdResolvedReason: z.string().nullable(),
  holdResolvedBy: z.string().nullable(),
  holdResolvedAt: z.string().nullable(),
  resolutionMovementId: z.string().uuid().nullable(),
  movementId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsReceiptLine = z.infer<typeof WmsReceiptLineSchema>;

export function parseWmsReceiptLine(row: Record<string, unknown>): WmsReceiptLine {
  return WmsReceiptLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    receiptSessionId: row.receipt_session_id,
    inboundOrderLineId: row.inbound_order_line_id,
    lineNumber: row.line_number,
    itemMasterId: row.item_master_id,
    ownerAccountId: row.owner_account_id,
    expectedUomCode: row.expected_uom_code,
    expectedQuantity: row.expected_quantity,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    countedUomCode: row.counted_uom_code ?? null,
    countedQuantity: row.counted_quantity,
    acceptedQuantity: row.accepted_quantity,
    damagedQuantity: row.damaged_quantity,
    heldQuantity: row.held_quantity,
    rejectedQuantity: row.rejected_quantity,
    overQuantity: row.over_quantity,
    shortQuantity: row.short_quantity,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    expiryDate: row.expiry_date ?? null,
    conditionNotes: row.condition_notes ?? null,
    status: row.status,
    overApproved: row.over_approved,
    overApprovedReason: row.over_approved_reason ?? null,
    overApprovedBy: row.over_approved_by ?? null,
    overApprovedAt: row.over_approved_at ?? null,
    holdResolved: row.hold_resolved,
    holdResolution: row.hold_resolution ?? null,
    holdResolvedReason: row.hold_resolved_reason ?? null,
    holdResolvedBy: row.hold_resolved_by ?? null,
    holdResolvedAt: row.hold_resolved_at ?? null,
    resolutionMovementId: row.resolution_movement_id ?? null,
    movementId: row.movement_id ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

// --- Mutation input schemas ---

export const StartWmsReceiptSessionInputSchema = z.object({
  inboundOrderId: z.string().uuid(),
  receivingLocationId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type StartWmsReceiptSessionInput = z.input<typeof StartWmsReceiptSessionInputSchema>;

export const RecordWmsReceiptLineCountInputSchema = z.object({
  lineId: z.string().uuid(),
  uomCode: z.string().nullable(),
  countedQuantity: z.number().min(0),
  acceptedQuantity: z.number().min(0),
  damagedQuantity: z.number().min(0),
  heldQuantity: z.number().min(0),
  rejectedQuantity: z.number().min(0),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  conditionNotes: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordWmsReceiptLineCountInput = z.input<typeof RecordWmsReceiptLineCountInputSchema>;

export const ApproveWmsReceiptOverageInputSchema = z.object({
  lineId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApproveWmsReceiptOverageInput = z.input<typeof ApproveWmsReceiptOverageInputSchema>;

export const CommitWmsReceiptLineInputSchema = z.object({
  lineId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CommitWmsReceiptLineInput = z.input<typeof CommitWmsReceiptLineInputSchema>;

export const CompleteWmsReceiptSessionInputSchema = z.object({
  sessionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CompleteWmsReceiptSessionInput = z.input<typeof CompleteWmsReceiptSessionInputSchema>;

export const CancelWmsReceiptSessionInputSchema = z.object({
  sessionId: z.string().uuid(),
  reason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelWmsReceiptSessionInput = z.input<typeof CancelWmsReceiptSessionInputSchema>;

export const ResolveWmsReceiptHoldInputSchema = z.object({
  lineId: z.string().uuid(),
  resolution: WmsReceiptHoldResolutionSchema,
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ResolveWmsReceiptHoldInput = z.input<typeof ResolveWmsReceiptHoldInputSchema>;
