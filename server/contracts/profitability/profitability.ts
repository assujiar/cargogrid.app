/**
 * Job, Customer and Service Profitability contract (FIN-212, CG-S9-FIN-023).
 * Mirrors supabase/migrations/20260729260000_create_finance_job_profitability.sql's
 * app.finance_job_profitability_facts shape and its calculate/get/summary RPCs.
 */

import { z } from "zod";

export const FINANCE_PROFITABILITY_STATUSES = ["calculated", "unavailable"] as const;
export const FinanceProfitabilityStatusSchema = z.enum(FINANCE_PROFITABILITY_STATUSES);
export type FinanceProfitabilityStatus = z.infer<typeof FinanceProfitabilityStatusSchema>;

export const FINANCE_PROFITABILITY_GROUP_BY_VALUES = ["customer", "branch", "service"] as const;
export const FinanceProfitabilityGroupBySchema = z.enum(FINANCE_PROFITABILITY_GROUP_BY_VALUES);
export type FinanceProfitabilityGroupBy = z.infer<typeof FinanceProfitabilityGroupBySchema>;

export const FinanceJobProfitabilityFactSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  jobOrderId: z.string().uuid(),
  versionNumber: z.number().int(),
  isCurrent: z.boolean(),
  status: FinanceProfitabilityStatusSchema,
  blockedReason: z.string().nullable(),
  revenueBasis: z.literal("billed"),
  revenueCurrency: z.string().nullable(),
  revenueAmount: z.number().nullable(),
  costCurrency: z.string().nullable(),
  costAmount: z.number().nullable(),
  profitAmount: z.number().nullable(),
  marginPercent: z.number().nullable(),
  sourceInvoiceIds: z.array(z.string().uuid()),
  sourceCostVersionIds: z.array(z.string().uuid()),
  recalculationReason: z.string().nullable(),
  calculatedByAuthUserId: z.string().uuid(),
  calculatedAt: z.string(),
  recordVersion: z.number().int(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type FinanceJobProfitabilityFact = z.infer<typeof FinanceJobProfitabilityFactSchema>;

export const FinanceProfitabilitySummaryRowSchema = z.object({
  dimensionKey: z.string().nullable(),
  dimensionLabel: z.string().nullable(),
  currency: z.string().nullable(),
  jobCount: z.number().int(),
  revenueAmount: z.number().nullable(),
  costAmount: z.number().nullable(),
  profitAmount: z.number().nullable(),
  marginPercent: z.number().nullable(),
});
export type FinanceProfitabilitySummaryRow = z.infer<typeof FinanceProfitabilitySummaryRowSchema>;

export const CalculateFinanceJobProfitabilityInputSchema = z.object({
  jobOrderId: z.string().uuid(),
  recalculationReason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CalculateFinanceJobProfitabilityInput = z.input<typeof CalculateFinanceJobProfitabilityInputSchema>;

const numeric = (value: unknown) => (typeof value === "string" ? Number(value) : value);

/** Maps a raw app.finance_job_profitability_facts row (snake_case) to this contract's camelCase shape. */
export function parseFinanceJobProfitabilityFact(row: Record<string, unknown>): FinanceJobProfitabilityFact {
  return FinanceJobProfitabilityFactSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    jobOrderId: row.job_order_id,
    versionNumber: row.version_number,
    isCurrent: row.is_current,
    status: row.status,
    blockedReason: row.blocked_reason ?? null,
    revenueBasis: row.revenue_basis,
    revenueCurrency: row.revenue_currency ?? null,
    revenueAmount: numeric(row.revenue_amount) ?? null,
    costCurrency: row.cost_currency ?? null,
    costAmount: numeric(row.cost_amount) ?? null,
    profitAmount: numeric(row.profit_amount) ?? null,
    marginPercent: numeric(row.margin_percent) ?? null,
    sourceInvoiceIds: Array.isArray(row.source_invoice_ids) ? row.source_invoice_ids : [],
    sourceCostVersionIds: Array.isArray(row.source_cost_version_ids) ? row.source_cost_version_ids : [],
    recalculationReason: row.recalculation_reason ?? null,
    calculatedByAuthUserId: row.calculated_by_auth_user_id,
    calculatedAt: row.calculated_at,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps a raw app.get_finance_profitability_summary row (snake_case) to this contract's camelCase shape. */
export function parseFinanceProfitabilitySummaryRow(row: Record<string, unknown>): FinanceProfitabilitySummaryRow {
  return FinanceProfitabilitySummaryRowSchema.parse({
    dimensionKey: row.dimension_key ?? null,
    dimensionLabel: row.dimension_label ?? null,
    currency: row.currency ?? null,
    jobCount: typeof row.job_count === "string" ? Number(row.job_count) : row.job_count,
    revenueAmount: numeric(row.revenue_amount) ?? null,
    costAmount: numeric(row.cost_amount) ?? null,
    profitAmount: numeric(row.profit_amount) ?? null,
    marginPercent: numeric(row.margin_percent) ?? null,
  });
}
