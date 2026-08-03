/**
 * WMS Putaway contract (ATW-014, CG-S10-ATW-014, Prompt 233). Mirrors
 * supabase/migrations/20260730210000_create_advanced_tms_wms_putaway.sql's
 * app.wms_putaway_tasks/app.wms_putaway_confirmations shapes and their
 * generate/claim/confirm/exception/reassign/cancel/read RPCs.
 */

import { z } from "zod";

export const WMS_PUTAWAY_TASK_STATUSES = ["unclaimed", "claimed", "partial", "confirmed", "exception", "cancelled"] as const;
export const WmsPutawayTaskStatusSchema = z.enum(WMS_PUTAWAY_TASK_STATUSES);
export type WmsPutawayTaskStatus = z.infer<typeof WmsPutawayTaskStatusSchema>;

export const WmsPutawayTaskSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  receiptLineId: z.string().uuid(),
  sourceLocationId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  uomCode: z.string(),
  lotControlled: z.boolean(),
  serialControlled: z.boolean(),
  expiryControlled: z.boolean(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  taskQuantity: z.coerce.number(),
  confirmedQuantity: z.coerce.number(),
  remainingQuantity: z.coerce.number(),
  suggestedLocationId: z.string().uuid().nullable(),
  suggestedReason: z.string().nullable(),
  actualLocationId: z.string().uuid().nullable(),
  status: WmsPutawayTaskStatusSchema,
  claimedByAuthUserId: z.string().uuid().nullable(),
  claimedByLabel: z.string().nullable(),
  claimedAt: z.string().nullable(),
  exceptionReason: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsPutawayTask = z.infer<typeof WmsPutawayTaskSchema>;

export function parseWmsPutawayTask(row: Record<string, unknown>): WmsPutawayTask {
  return WmsPutawayTaskSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    receiptLineId: row.receipt_line_id,
    sourceLocationId: row.source_location_id,
    itemMasterId: row.item_master_id,
    ownerAccountId: row.owner_account_id,
    uomCode: row.uom_code,
    lotControlled: row.lot_controlled,
    serialControlled: row.serial_controlled,
    expiryControlled: row.expiry_controlled,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    expiryDate: row.expiry_date ?? null,
    taskQuantity: row.task_quantity,
    confirmedQuantity: row.confirmed_quantity,
    remainingQuantity: row.remaining_quantity,
    suggestedLocationId: row.suggested_location_id ?? null,
    suggestedReason: row.suggested_reason ?? null,
    actualLocationId: row.actual_location_id ?? null,
    status: row.status,
    claimedByAuthUserId: row.claimed_by_auth_user_id ?? null,
    claimedByLabel: row.claimed_by_label ?? null,
    claimedAt: row.claimed_at ?? null,
    exceptionReason: row.exception_reason ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsPutawayConfirmationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  taskId: z.string().uuid(),
  idempotencyKey: z.string(),
  quantity: z.coerce.number(),
  actualLocationId: z.string().uuid(),
  movementId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  confirmedByAuthUserId: z.string().uuid().nullable(),
  confirmedByLabel: z.string().nullable(),
  confirmedAt: z.string(),
});
export type WmsPutawayConfirmation = z.infer<typeof WmsPutawayConfirmationSchema>;

export function parseWmsPutawayConfirmation(row: Record<string, unknown>): WmsPutawayConfirmation {
  return WmsPutawayConfirmationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    taskId: row.task_id,
    idempotencyKey: row.idempotency_key,
    quantity: row.quantity,
    actualLocationId: row.actual_location_id,
    movementId: row.movement_id,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    expiryDate: row.expiry_date ?? null,
    confirmedByAuthUserId: row.confirmed_by_auth_user_id ?? null,
    confirmedByLabel: row.confirmed_by_label ?? null,
    confirmedAt: row.confirmed_at,
  });
}

// --- Mutation input schemas ---

export const GenerateWmsPutawayTaskInputSchema = z.object({
  receiptLineId: z.string().uuid(),
  quantity: z.number().positive(),
  suggestedLocationId: z.string().uuid().nullable(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type GenerateWmsPutawayTaskInput = z.input<typeof GenerateWmsPutawayTaskInputSchema>;

export const ClaimWmsPutawayTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ClaimWmsPutawayTaskInput = z.input<typeof ClaimWmsPutawayTaskInputSchema>;

export const ConfirmWmsPutawayTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  quantity: z.number().positive(),
  actualLocationId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConfirmWmsPutawayTaskInput = z.input<typeof ConfirmWmsPutawayTaskInputSchema>;

export const MarkWmsPutawayTaskExceptionInputSchema = z.object({
  taskId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type MarkWmsPutawayTaskExceptionInput = z.input<typeof MarkWmsPutawayTaskExceptionInputSchema>;

export const ReassignWmsPutawayTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  newClaimantAuthUserId: z.string().uuid().nullable(),
  newClaimantLabel: z.string().nullable(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReassignWmsPutawayTaskInput = z.input<typeof ReassignWmsPutawayTaskInputSchema>;

export const CancelWmsPutawayTaskInputSchema = z.object({
  taskId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelWmsPutawayTaskInput = z.input<typeof CancelWmsPutawayTaskInputSchema>;
