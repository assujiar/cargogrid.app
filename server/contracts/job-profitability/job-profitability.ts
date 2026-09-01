/**
 * Basic Job Profitability contract (OPS-179, CG-S8-OPS-013). Mirrors
 * supabase/migrations/20260728120000_create_operations_job_profitability.sql's
 * app.job_profitability_snapshots shape and its RPC.
 *
 * A deterministic, versioned operational-margin snapshot from the Job Order's own
 * pinned Commercial revenue and every approved OPS-178 actual-cost version --
 * operational profitability only, never accounting P&L.
 */

import { z } from "zod";

export const JobProfitabilitySnapshotSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isCurrent: z.boolean(),
  status: z.enum(["calculated", "unavailable"]),
  blockedReason: z.string().nullable(),
  /** ISS-2026-197: fixed marker distinguishing this quote-time operational estimate from app.finance_job_profitability_facts' own 'billed' basis. Metadata, never null even when status is unavailable. */
  revenueBasis: z.literal("quoted"),
  revenueCurrency: z.string().nullable(),
  revenueAmount: z.number().nullable(),
  costCurrency: z.string().nullable(),
  costAmount: z.number().nullable(),
  marginAmount: z.number().nullable(),
  marginPercent: z.number().nullable(),
  sourceCostVersionIds: z.array(z.string().uuid()),
  recalculationReason: z.string().nullable(),
  calculatedByAuthUserId: z.string().uuid(),
  calculatedAt: z.string(),
  recordVersion: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type JobProfitabilitySnapshot = z.infer<typeof JobProfitabilitySnapshotSchema>;

function toNullableNumber(value: unknown): number | null {
  return value === null || value === undefined ? null : Number(value);
}

export function parseJobProfitabilitySnapshot(row: Record<string, unknown>): JobProfitabilitySnapshot {
  return JobProfitabilitySnapshotSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobOrderId: row.job_order_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    status: row.status,
    blockedReason: row.blocked_reason ?? null,
    revenueBasis: row.revenue_basis,
    revenueCurrency: row.revenue_currency ?? null,
    revenueAmount: toNullableNumber(row.revenue_amount),
    costCurrency: row.cost_currency ?? null,
    costAmount: toNullableNumber(row.cost_amount),
    marginAmount: toNullableNumber(row.margin_amount),
    marginPercent: toNullableNumber(row.margin_percent),
    sourceCostVersionIds: row.source_cost_version_ids ?? [],
    recalculationReason: row.recalculation_reason ?? null,
    calculatedByAuthUserId: row.calculated_by_auth_user_id,
    calculatedAt: row.calculated_at,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.job_profitability_directory's own row shape -- revenue/cost/margin amounts and source_cost_version_ids are null/empty (marginMasked=true) for an actor lacking OPS:View margin. */
export const JobProfitabilityDirectoryRowSchema = JobProfitabilitySnapshotSchema.extend({
  marginMasked: z.boolean(),
});
export type JobProfitabilityDirectoryRow = z.infer<typeof JobProfitabilityDirectoryRowSchema>;

export function parseJobProfitabilityDirectoryRow(row: Record<string, unknown>): JobProfitabilityDirectoryRow {
  return JobProfitabilityDirectoryRowSchema.parse({
    ...parseJobProfitabilitySnapshot(row),
    marginMasked: row.margin_masked,
  });
}

export const CalculateJobProfitabilityInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  recalculationReason: z.string().nullable().optional(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CalculateJobProfitabilityInput = z.input<typeof CalculateJobProfitabilityInputSchema>;
