/**
 * Cycle Count and Inventory Adjustment contract (ATW-020, CG-S10-ATW-020, Prompt
 * 239). Mirrors
 * supabase/migrations/20260730270000_create_advanced_tms_cycle_count_adjustment.sql's
 * app.cycle_count_plans/app.cycle_count_scope_items/app.cycle_count_observations
 * shapes and their create/freeze/assign/record-observation/approve/reject/cancel/
 * close/read RPCs.
 *
 * Blind-count redaction (the migration's own design note 6): a plain OPS:Edit-only
 * counter's own read RPC responses come back with snapshotExpectedQuantity/
 * varianceQuantity/variancePct/snapshotRecordVersion all null -- computed server-side
 * from the actor's real RBAC grant, never a client-supplied flag. The zod schemas
 * below accept null for those four fields for exactly that reason.
 */

import { z } from "zod";

export const CYCLE_COUNT_PLAN_METHODS = ["full", "abc", "spot"] as const;
export const CycleCountPlanMethodSchema = z.enum(CYCLE_COUNT_PLAN_METHODS);
export type CycleCountPlanMethod = z.infer<typeof CycleCountPlanMethodSchema>;

export const CYCLE_COUNT_PLAN_STATUSES = ["draft", "active", "closed", "cancelled"] as const;
export const CycleCountPlanStatusSchema = z.enum(CYCLE_COUNT_PLAN_STATUSES);
export type CycleCountPlanStatus = z.infer<typeof CycleCountPlanStatusSchema>;

export const CYCLE_COUNT_SCOPE_ITEM_STATUSES = [
  "pending",
  "assigned",
  "recount_required",
  "pending_review",
  "adjusted",
  "no_variance_closed",
  "cancelled",
] as const;
export const CycleCountScopeItemStatusSchema = z.enum(CYCLE_COUNT_SCOPE_ITEM_STATUSES);
export type CycleCountScopeItemStatus = z.infer<typeof CycleCountScopeItemStatusSchema>;

export const CycleCountPlanSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  planNumber: z.string(),
  method: CycleCountPlanMethodSchema,
  varianceThresholdPct: z.coerce.number(),
  recountThresholdPct: z.coerce.number(),
  requiresSeparateApprover: z.boolean(),
  status: CycleCountPlanStatusSchema,
  scopeFilterZoneId: z.string().uuid().nullable(),
  scopeFilterLocationId: z.string().uuid().nullable(),
  scopeFilterItemMasterId: z.string().uuid().nullable(),
  scopeFilterOwnerAccountId: z.string().uuid().nullable(),
  frozenAt: z.string().nullable(),
  closedAt: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CycleCountPlan = z.infer<typeof CycleCountPlanSchema>;

export function parseCycleCountPlan(row: Record<string, unknown>): CycleCountPlan {
  return CycleCountPlanSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    planNumber: row.plan_number,
    method: row.method,
    varianceThresholdPct: row.variance_threshold_pct,
    recountThresholdPct: row.recount_threshold_pct,
    requiresSeparateApprover: row.requires_separate_approver,
    status: row.status,
    scopeFilterZoneId: row.scope_filter_zone_id ?? null,
    scopeFilterLocationId: row.scope_filter_location_id ?? null,
    scopeFilterItemMasterId: row.scope_filter_item_master_id ?? null,
    scopeFilterOwnerAccountId: row.scope_filter_owner_account_id ?? null,
    frozenAt: row.frozen_at ?? null,
    closedAt: row.closed_at ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CycleCountScopeItemSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  planId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  locationId: z.string().uuid(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  uomCode: z.string(),
  snapshotBalanceId: z.string().uuid(),
  // Nullable: blind-count redaction (design note 6) nulls this out for a plain
  // OPS:Edit-only counter's own read responses.
  snapshotExpectedQuantity: z.coerce.number().nullable(),
  snapshotRecordVersion: z.number().int().nullable(),
  snapshotTakenAt: z.string(),
  status: CycleCountScopeItemStatusSchema,
  assignedToAuthUserId: z.string().uuid().nullable(),
  assignedToLabel: z.string().nullable(),
  assignedAt: z.string().nullable(),
  countAttemptNumber: z.number().int(),
  lastObservedQuantity: z.coerce.number().nullable(),
  varianceQuantity: z.coerce.number().nullable(),
  variancePct: z.coerce.number().nullable(),
  reviewedByAuthUserId: z.string().uuid().nullable(),
  reviewedByLabel: z.string().nullable(),
  reviewedAt: z.string().nullable(),
  reviewReason: z.string().nullable(),
  adjustmentMovementId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CycleCountScopeItem = z.infer<typeof CycleCountScopeItemSchema>;

export function parseCycleCountScopeItem(row: Record<string, unknown>): CycleCountScopeItem {
  return CycleCountScopeItemSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    planId: row.plan_id,
    warehouseId: row.warehouse_id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    locationId: row.location_id,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    uomCode: row.uom_code,
    snapshotBalanceId: row.snapshot_balance_id,
    snapshotExpectedQuantity: row.snapshot_expected_quantity ?? null,
    snapshotRecordVersion: row.snapshot_record_version ?? null,
    snapshotTakenAt: row.snapshot_taken_at,
    status: row.status,
    assignedToAuthUserId: row.assigned_to_auth_user_id ?? null,
    assignedToLabel: row.assigned_to_label ?? null,
    assignedAt: row.assigned_at ?? null,
    countAttemptNumber: row.count_attempt_number,
    lastObservedQuantity: row.last_observed_quantity ?? null,
    varianceQuantity: row.variance_quantity ?? null,
    variancePct: row.variance_pct ?? null,
    reviewedByAuthUserId: row.reviewed_by_auth_user_id ?? null,
    reviewedByLabel: row.reviewed_by_label ?? null,
    reviewedAt: row.reviewed_at ?? null,
    reviewReason: row.review_reason ?? null,
    adjustmentMovementId: row.adjustment_movement_id ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const CycleCountObservationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  scopeItemId: z.string().uuid(),
  attemptNumber: z.number().int().positive(),
  observedQuantity: z.coerce.number(),
  observedUomCode: z.string(),
  scannedLocationId: z.string().uuid(),
  scannedItemMasterId: z.string().uuid(),
  scannedLotNumber: z.string().nullable(),
  scannedSerialNumber: z.string().nullable(),
  idempotencyKey: z.string(),
  countedByAuthUserId: z.string().uuid().nullable(),
  countedByLabel: z.string().nullable(),
  countedAt: z.string(),
});
export type CycleCountObservation = z.infer<typeof CycleCountObservationSchema>;

export function parseCycleCountObservation(row: Record<string, unknown>): CycleCountObservation {
  return CycleCountObservationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    scopeItemId: row.scope_item_id,
    attemptNumber: row.attempt_number,
    observedQuantity: row.observed_quantity,
    observedUomCode: row.observed_uom_code,
    scannedLocationId: row.scanned_location_id,
    scannedItemMasterId: row.scanned_item_master_id,
    scannedLotNumber: row.scanned_lot_number ?? null,
    scannedSerialNumber: row.scanned_serial_number ?? null,
    idempotencyKey: row.idempotency_key,
    countedByAuthUserId: row.counted_by_auth_user_id ?? null,
    countedByLabel: row.counted_by_label ?? null,
    countedAt: row.counted_at,
  });
}

// --- Mutation input schemas ---

export const CreateCycleCountPlanInputSchema = z.object({
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  method: CycleCountPlanMethodSchema.optional(),
  varianceThresholdPct: z.number().min(0),
  recountThresholdPct: z.number().min(0),
  requiresSeparateApprover: z.boolean().optional(),
  scopeFilterZoneId: z.string().uuid().nullable().optional(),
  scopeFilterLocationId: z.string().uuid().nullable().optional(),
  scopeFilterItemMasterId: z.string().uuid().nullable().optional(),
  scopeFilterOwnerAccountId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateCycleCountPlanInput = z.input<typeof CreateCycleCountPlanInputSchema>;

export const FreezeCycleCountScopeInputSchema = z.object({
  planId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type FreezeCycleCountScopeInput = z.input<typeof FreezeCycleCountScopeInputSchema>;

export const CancelCycleCountPlanInputSchema = z.object({
  planId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelCycleCountPlanInput = z.input<typeof CancelCycleCountPlanInputSchema>;

export const CloseCycleCountPlanInputSchema = z.object({
  planId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CloseCycleCountPlanInput = z.input<typeof CloseCycleCountPlanInputSchema>;

export const AssignCycleCountScopeItemInputSchema = z.object({
  scopeItemId: z.string().uuid(),
  assigneeAuthUserId: z.string().uuid(),
  assigneeLabel: z.string(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AssignCycleCountScopeItemInput = z.input<typeof AssignCycleCountScopeItemInputSchema>;

export const RecordCycleCountObservationInputSchema = z.object({
  scopeItemId: z.string().uuid(),
  observedQuantity: z.number().min(0),
  observedUomCode: z.string().min(1),
  scannedLocationId: z.string().uuid(),
  scannedItemMasterId: z.string().uuid(),
  scannedLotNumber: z.string().nullable().optional(),
  scannedSerialNumber: z.string().nullable().optional(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordCycleCountObservationInput = z.input<typeof RecordCycleCountObservationInputSchema>;

export const ApproveCycleCountVarianceInputSchema = z.object({
  scopeItemId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApproveCycleCountVarianceInput = z.input<typeof ApproveCycleCountVarianceInputSchema>;

export const RejectCycleCountVarianceInputSchema = z.object({
  scopeItemId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RejectCycleCountVarianceInput = z.input<typeof RejectCycleCountVarianceInputSchema>;

export const CancelCycleCountScopeItemInputSchema = z.object({
  scopeItemId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelCycleCountScopeItemInput = z.input<typeof CancelCycleCountScopeItemInputSchema>;
