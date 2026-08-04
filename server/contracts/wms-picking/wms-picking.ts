/**
 * WMS Picking contract (ATW-017, CG-S10-ATW-017, Prompt 236). Mirrors
 * supabase/migrations/20260730240000_create_advanced_tms_wms_picking.sql's
 * app.wms_pick_waves/app.wms_pick_tasks/app.wms_pick_task_confirmations/
 * app.wms_pick_task_shorts/app.wms_pick_substitution_approvals shapes and their
 * create-wave/generate/claim/confirm/record-short/exception/reassign/cancel/
 * approve-substitution/read RPCs.
 */

import { z } from "zod";

export const WMS_PICK_TASK_STATUSES = ["unclaimed", "claimed", "partial", "picked", "short", "exception", "cancelled"] as const;
export const WmsPickTaskStatusSchema = z.enum(WMS_PICK_TASK_STATUSES);
export type WmsPickTaskStatus = z.infer<typeof WmsPickTaskStatusSchema>;

export const WmsPickWaveSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  waveNumber: z.string(),
  idempotencyKey: z.string(),
  createdAt: z.string(),
});
export type WmsPickWave = z.infer<typeof WmsPickWaveSchema>;

export function parseWmsPickWave(row: Record<string, unknown>): WmsPickWave {
  return WmsPickWaveSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    waveNumber: row.wave_number,
    idempotencyKey: row.idempotency_key,
    createdAt: row.created_at,
  });
}

export const WmsPickTaskSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  outboundOrderId: z.string().uuid(),
  outboundOrderLineId: z.string().uuid(),
  waveId: z.string().uuid().nullable(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  uomCode: z.string(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  sourceLocationId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  reservationId: z.string().uuid(),
  taskQuantity: z.coerce.number(),
  pickedQuantity: z.coerce.number(),
  shortQuantity: z.coerce.number(),
  remainingQuantity: z.coerce.number(),
  suggestedDestinationLocationId: z.string().uuid().nullable(),
  suggestedDestinationReason: z.string().nullable(),
  actualDestinationLocationId: z.string().uuid().nullable(),
  status: WmsPickTaskStatusSchema,
  claimedByAuthUserId: z.string().uuid().nullable(),
  claimedByLabel: z.string().nullable(),
  claimedAt: z.string().nullable(),
  exceptionReason: z.string().nullable(),
  substitutedFromItemMasterId: z.string().uuid().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsPickTask = z.infer<typeof WmsPickTaskSchema>;

export function parseWmsPickTask(row: Record<string, unknown>): WmsPickTask {
  return WmsPickTaskSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    outboundOrderId: row.outbound_order_id,
    outboundOrderLineId: row.outbound_order_line_id,
    waveId: row.wave_id ?? null,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    uomCode: row.uom_code,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    sourceLocationId: row.source_location_id,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    expiryDate: row.expiry_date ?? null,
    reservationId: row.reservation_id,
    taskQuantity: row.task_quantity,
    pickedQuantity: row.picked_quantity,
    shortQuantity: row.short_quantity,
    remainingQuantity: row.remaining_quantity,
    suggestedDestinationLocationId: row.suggested_destination_location_id ?? null,
    suggestedDestinationReason: row.suggested_destination_reason ?? null,
    actualDestinationLocationId: row.actual_destination_location_id ?? null,
    status: row.status,
    claimedByAuthUserId: row.claimed_by_auth_user_id ?? null,
    claimedByLabel: row.claimed_by_label ?? null,
    claimedAt: row.claimed_at ?? null,
    exceptionReason: row.exception_reason ?? null,
    substitutedFromItemMasterId: row.substituted_from_item_master_id ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsPickTaskConfirmationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  taskId: z.string().uuid(),
  idempotencyKey: z.string(),
  quantity: z.coerce.number(),
  scannedLocationId: z.string().uuid(),
  scannedItemMasterId: z.string().uuid(),
  scannedLotNumber: z.string().nullable(),
  scannedSerialNumber: z.string().nullable(),
  actualDestinationLocationId: z.string().uuid(),
  movementId: z.string().uuid(),
  confirmedByAuthUserId: z.string().uuid().nullable(),
  confirmedByLabel: z.string().nullable(),
  confirmedAt: z.string(),
});
export type WmsPickTaskConfirmation = z.infer<typeof WmsPickTaskConfirmationSchema>;

export function parseWmsPickTaskConfirmation(row: Record<string, unknown>): WmsPickTaskConfirmation {
  return WmsPickTaskConfirmationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    taskId: row.task_id,
    idempotencyKey: row.idempotency_key,
    quantity: row.quantity,
    scannedLocationId: row.scanned_location_id,
    scannedItemMasterId: row.scanned_item_master_id,
    scannedLotNumber: row.scanned_lot_number ?? null,
    scannedSerialNumber: row.scanned_serial_number ?? null,
    actualDestinationLocationId: row.actual_destination_location_id,
    movementId: row.movement_id,
    confirmedByAuthUserId: row.confirmed_by_auth_user_id ?? null,
    confirmedByLabel: row.confirmed_by_label ?? null,
    confirmedAt: row.confirmed_at,
  });
}

export const WmsPickTaskShortSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  taskId: z.string().uuid(),
  idempotencyKey: z.string(),
  quantity: z.coerce.number(),
  reason: z.string(),
  recordedByAuthUserId: z.string().uuid().nullable(),
  recordedByLabel: z.string().nullable(),
  recordedAt: z.string(),
});
export type WmsPickTaskShort = z.infer<typeof WmsPickTaskShortSchema>;

export function parseWmsPickTaskShort(row: Record<string, unknown>): WmsPickTaskShort {
  return WmsPickTaskShortSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    taskId: row.task_id,
    idempotencyKey: row.idempotency_key,
    quantity: row.quantity,
    reason: row.reason,
    recordedByAuthUserId: row.recorded_by_auth_user_id ?? null,
    recordedByLabel: row.recorded_by_label ?? null,
    recordedAt: row.recorded_at,
  });
}

export const WmsPickSubstitutionApprovalSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  taskId: z.string().uuid(),
  originalItemMasterId: z.string().uuid(),
  substituteItemMasterId: z.string().uuid(),
  originalReservationId: z.string().uuid(),
  newReservationId: z.string().uuid(),
  reason: z.string(),
  idempotencyKey: z.string(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  approvedByLabel: z.string().nullable(),
  approvedAt: z.string(),
});
export type WmsPickSubstitutionApproval = z.infer<typeof WmsPickSubstitutionApprovalSchema>;

export function parseWmsPickSubstitutionApproval(row: Record<string, unknown>): WmsPickSubstitutionApproval {
  return WmsPickSubstitutionApprovalSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    taskId: row.task_id,
    originalItemMasterId: row.original_item_master_id,
    substituteItemMasterId: row.substitute_item_master_id,
    originalReservationId: row.original_reservation_id,
    newReservationId: row.new_reservation_id,
    reason: row.reason,
    idempotencyKey: row.idempotency_key,
    approvedByAuthUserId: row.approved_by_auth_user_id ?? null,
    approvedByLabel: row.approved_by_label ?? null,
    approvedAt: row.approved_at,
  });
}

// --- Mutation input schemas ---

export const CreateWmsPickWaveInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateWmsPickWaveInput = z.input<typeof CreateWmsPickWaveInputSchema>;

export const GenerateWmsPickTaskInputSchema = z.object({
  outboundOrderLineId: z.string().uuid(),
  quantity: z.number().positive(),
  waveId: z.string().uuid().nullable(),
  locationId: z.string().uuid().nullable(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  suggestedDestinationLocationId: z.string().uuid().nullable(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type GenerateWmsPickTaskInput = z.input<typeof GenerateWmsPickTaskInputSchema>;

export const ClaimWmsPickTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ClaimWmsPickTaskInput = z.input<typeof ClaimWmsPickTaskInputSchema>;

export const ConfirmWmsPickTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  quantity: z.number().positive(),
  scannedLocationId: z.string().uuid(),
  scannedItemMasterId: z.string().uuid(),
  scannedLotNumber: z.string().nullable(),
  scannedSerialNumber: z.string().nullable(),
  actualDestinationLocationId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConfirmWmsPickTaskInput = z.input<typeof ConfirmWmsPickTaskInputSchema>;

export const RecordWmsPickTaskShortInputSchema = z.object({
  taskId: z.string().uuid(),
  shortQuantity: z.number().positive(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordWmsPickTaskShortInput = z.input<typeof RecordWmsPickTaskShortInputSchema>;

export const MarkWmsPickTaskExceptionInputSchema = z.object({
  taskId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type MarkWmsPickTaskExceptionInput = z.input<typeof MarkWmsPickTaskExceptionInputSchema>;

export const ReassignWmsPickTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  newClaimantAuthUserId: z.string().uuid().nullable(),
  newClaimantLabel: z.string().nullable(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReassignWmsPickTaskInput = z.input<typeof ReassignWmsPickTaskInputSchema>;

export const CancelWmsPickTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelWmsPickTaskInput = z.input<typeof CancelWmsPickTaskInputSchema>;

export const ApproveWmsPickSubstitutionInputSchema = z.object({
  taskId: z.string().uuid(),
  substituteItemMasterId: z.string().uuid(),
  locationId: z.string().uuid().nullable(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApproveWmsPickSubstitutionInput = z.input<typeof ApproveWmsPickSubstitutionInputSchema>;
