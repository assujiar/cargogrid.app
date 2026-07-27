/**
 * Job Order contract (OPS-168, CG-S8-OPS-002). Mirrors
 * supabase/migrations/20260727090000_create_operations_job_order.sql's
 * app.job_orders/app.job_order_overrides/app.job_orders_directory shape and their RPCs.
 *
 * The canonical Operations execution root -- one row per converted Commercial
 * JobOrderDraftInput handoff (COM-160). Every snapshot column below is a verbatim
 * copy of the handoff's own payload sub-object, never a live re-typed value.
 */

import { z } from "zod";

export const JOB_ORDER_STATUSES = ["draft", "confirmed", "cancelled"] as const;
export const JobOrderStatusSchema = z.enum(JOB_ORDER_STATUSES);
export type JobOrderStatus = z.infer<typeof JobOrderStatusSchema>;

export const OVERRIDABLE_SNAPSHOT_COLUMNS = ["customer_snapshot", "cargo_service_snapshot"] as const;
export const OverridableSnapshotColumnSchema = z.enum(OVERRIDABLE_SNAPSHOT_COLUMNS);
export type OverridableSnapshotColumn = z.infer<typeof OverridableSnapshotColumnSchema>;

/** Field-masked projection of app.job_orders -- revenue_snapshot/credit_snapshot are nulled (masked=true) without COM:View selling price/COM:View cost respectively. */
export const JobOrderSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobNumber: z.string(),
  sourceHandoffId: z.string().uuid(),
  quotationId: z.string().uuid(),
  accountId: z.string().uuid(),
  customerSnapshot: z.record(z.string(), z.unknown()),
  cargoServiceSnapshot: z.record(z.string(), z.unknown()),
  revenueSnapshot: z.record(z.string(), z.unknown()).nullable(),
  revenueMasked: z.boolean(),
  contractSnapshot: z.record(z.string(), z.unknown()).nullable(),
  creditSnapshot: z.record(z.string(), z.unknown()).nullable(),
  creditMasked: z.boolean(),
  acceptanceSnapshot: z.record(z.string(), z.unknown()),
  status: JobOrderStatusSchema,
  ownerUserId: z.string().uuid().nullable(),
  orgUnitId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type JobOrder = z.infer<typeof JobOrderSchema>;

/** Maps a raw app.job_orders_directory row (snake_case) to this contract's camelCase shape. */
export function parseJobOrder(row: Record<string, unknown>): JobOrder {
  return JobOrderSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobNumber: row.job_number,
    sourceHandoffId: row.source_handoff_id,
    quotationId: row.quotation_id,
    accountId: row.account_id,
    customerSnapshot: row.customer_snapshot,
    cargoServiceSnapshot: row.cargo_service_snapshot,
    revenueSnapshot: row.revenue_snapshot ?? null,
    revenueMasked: row.revenue_masked,
    contractSnapshot: row.contract_snapshot ?? null,
    creditSnapshot: row.credit_snapshot ?? null,
    creditMasked: row.credit_masked,
    acceptanceSnapshot: row.acceptance_snapshot,
    status: row.status,
    ownerUserId: row.owner_user_id,
    orgUnitId: row.org_unit_id,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Append-only evidence row from app.job_order_overrides. */
export const JobOrderOverrideSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  snapshotColumn: OverridableSnapshotColumnSchema,
  fieldPath: z.string(),
  previousValue: z.unknown().nullable(),
  newValue: z.unknown(),
  reason: z.string(),
  overriddenBy: z.string().nullable(),
  overriddenAt: z.string(),
});
export type JobOrderOverride = z.infer<typeof JobOrderOverrideSchema>;

export function parseJobOrderOverride(row: Record<string, unknown>): JobOrderOverride {
  return JobOrderOverrideSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobOrderId: row.job_order_id,
    snapshotColumn: row.snapshot_column,
    fieldPath: row.field_path,
    previousValue: row.previous_value ?? null,
    newValue: row.new_value,
    reason: row.reason,
    overriddenBy: row.overridden_by,
    overriddenAt: row.overridden_at,
  });
}

/** app.get_job_order_conversion_readiness's own return row. */
export const JobOrderConversionReadinessSchema = z.object({
  ready: z.boolean(),
  blockingReasons: z.array(z.string()),
  existingJobOrderId: z.string().uuid().nullable(),
});
export type JobOrderConversionReadiness = z.infer<typeof JobOrderConversionReadinessSchema>;

export function parseJobOrderConversionReadiness(row: Record<string, unknown>): JobOrderConversionReadiness {
  return JobOrderConversionReadinessSchema.parse({
    ready: row.ready,
    blockingReasons: row.blocking_reasons ?? [],
    existingJobOrderId: row.existing_job_order_id ?? null,
  });
}

export const GetJobOrderConversionReadinessInputSchema = z.object({
  sourceHandoffId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetJobOrderConversionReadinessInput = z.input<typeof GetJobOrderConversionReadinessInputSchema>;

export const PrepareJobOrderInputSchema = z.object({
  sourceHandoffId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type PrepareJobOrderInput = z.input<typeof PrepareJobOrderInputSchema>;

export const ConfirmJobOrderInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ConfirmJobOrderInput = z.input<typeof ConfirmJobOrderInputSchema>;

export const OverrideJobOrderFieldInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  snapshotColumn: OverridableSnapshotColumnSchema,
  fieldPath: z.string().min(1),
  newValue: z.unknown(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type OverrideJobOrderFieldInput = z.input<typeof OverrideJobOrderFieldInputSchema>;
