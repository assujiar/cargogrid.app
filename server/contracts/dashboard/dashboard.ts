/**
 * Commercial Dashboard contract (COM-158, CG-S7-COM-017). Mirrors
 * supabase/migrations/20260724320000_create_commercial_dashboard.sql's seven
 * app.get_dashboard_* RPC result shapes. Every amount-bearing row carries its own
 * `currency` and a `*Masked` flag -- callers must never treat a masked null as zero.
 */

import { z } from "zod";

export const LEAD_AGING_BUCKETS = ["0_2_days", "3_7_days", "8_14_days", "15_plus_days"] as const;
export const LeadAgingBucketSchema = z.enum(LEAD_AGING_BUCKETS);
export type LeadAgingBucket = z.infer<typeof LeadAgingBucketSchema>;

export const ACTIVITY_QUEUE_BUCKETS = ["overdue", "due_today", "upcoming_7_days", "no_due_date"] as const;
export const ActivityQueueBucketSchema = z.enum(ACTIVITY_QUEUE_BUCKETS);
export type ActivityQueueBucket = z.infer<typeof ActivityQueueBucketSchema>;

export const QUOTE_SLA_BUCKETS = ["pending_approval", "expiring_soon", "expired_no_decision", "awaiting_customer_decision"] as const;
export const QuoteSlaBucketSchema = z.enum(QUOTE_SLA_BUCKETS);
export type QuoteSlaBucket = z.infer<typeof QuoteSlaBucketSchema>;

export const OPPORTUNITY_STAGES = ["qualifying", "requirements_gathering", "ready_for_costing", "won", "lost"] as const;
export const OpportunityStageSchema = z.enum(OPPORTUNITY_STAGES);
export type OpportunityStage = z.infer<typeof OpportunityStageSchema>;

export const WIN_LOSS_OUTCOMES = ["won", "lost"] as const;
export const WinLossOutcomeSchema = z.enum(WIN_LOSS_OUTCOMES);
export type WinLossOutcome = z.infer<typeof WinLossOutcomeSchema>;

/** Shared scope filter accepted by every app.get_dashboard_* function. */
export const DashboardScopeFilterSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable().default(null),
  ownerUserId: z.string().uuid().nullable().default(null),
});
export type DashboardScopeFilter = z.input<typeof DashboardScopeFilterSchema>;

/** Adds the optional [periodStart, periodEnd] window app.get_dashboard_margin_summary / app.get_dashboard_win_loss_summary accept -- ISO date strings (YYYY-MM-DD), never a timestamp. */
export const DashboardPeriodFilterSchema = DashboardScopeFilterSchema.extend({
  periodStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().default(null),
  periodEnd: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().default(null),
});
export type DashboardPeriodFilter = z.input<typeof DashboardPeriodFilterSchema>;

export const LeadAgingEntrySchema = z.object({
  bucket: LeadAgingBucketSchema,
  leadCount: z.coerce.number().int().nonnegative(),
});
export type LeadAgingEntry = z.infer<typeof LeadAgingEntrySchema>;

export function parseLeadAgingEntry(row: Record<string, unknown>): LeadAgingEntry {
  return LeadAgingEntrySchema.parse({ bucket: row.bucket, leadCount: row.lead_count });
}

export const ActivityQueueEntrySchema = z.object({
  bucket: ActivityQueueBucketSchema,
  activityCount: z.coerce.number().int().nonnegative(),
});
export type ActivityQueueEntry = z.infer<typeof ActivityQueueEntrySchema>;

export function parseActivityQueueEntry(row: Record<string, unknown>): ActivityQueueEntry {
  return ActivityQueueEntrySchema.parse({ bucket: row.bucket, activityCount: row.activity_count });
}

export const PipelineSummaryEntrySchema = z.object({
  stage: OpportunityStageSchema,
  currency: z.string().nullable(),
  opportunityCount: z.coerce.number().int().nonnegative(),
  valueAmountTotal: z.coerce.number().nullable(),
  valueMasked: z.boolean(),
});
export type PipelineSummaryEntry = z.infer<typeof PipelineSummaryEntrySchema>;

export function parsePipelineSummaryEntry(row: Record<string, unknown>): PipelineSummaryEntry {
  return PipelineSummaryEntrySchema.parse({
    stage: row.stage,
    currency: row.currency,
    opportunityCount: row.opportunity_count,
    valueAmountTotal: row.value_amount_total,
    valueMasked: row.value_masked,
  });
}

export const QuoteSlaEntrySchema = z.object({
  bucket: QuoteSlaBucketSchema,
  quoteCount: z.coerce.number().int().nonnegative(),
});
export type QuoteSlaEntry = z.infer<typeof QuoteSlaEntrySchema>;

export function parseQuoteSlaEntry(row: Record<string, unknown>): QuoteSlaEntry {
  return QuoteSlaEntrySchema.parse({ bucket: row.bucket, quoteCount: row.quote_count });
}

export const MarginSummaryEntrySchema = z.object({
  currency: z.string(),
  calculationCount: z.coerce.number().int().nonnegative(),
  avgMarginPct: z.coerce.number().nullable(),
  totalMarginAmount: z.coerce.number().nullable(),
  marginMasked: z.boolean(),
});
export type MarginSummaryEntry = z.infer<typeof MarginSummaryEntrySchema>;

export function parseMarginSummaryEntry(row: Record<string, unknown>): MarginSummaryEntry {
  return MarginSummaryEntrySchema.parse({
    currency: row.currency,
    calculationCount: row.calculation_count,
    avgMarginPct: row.avg_margin_pct,
    totalMarginAmount: row.total_margin_amount,
    marginMasked: row.margin_masked,
  });
}

export const WinLossSummaryEntrySchema = z.object({
  outcome: WinLossOutcomeSchema,
  currency: z.string().nullable(),
  opportunityCount: z.coerce.number().int().nonnegative(),
  valueAmountTotal: z.coerce.number().nullable(),
  valueMasked: z.boolean(),
});
export type WinLossSummaryEntry = z.infer<typeof WinLossSummaryEntrySchema>;

export function parseWinLossSummaryEntry(row: Record<string, unknown>): WinLossSummaryEntry {
  return WinLossSummaryEntrySchema.parse({
    outcome: row.outcome,
    currency: row.currency,
    opportunityCount: row.opportunity_count,
    valueAmountTotal: row.value_amount_total,
    valueMasked: row.value_masked,
  });
}

export const ForecastSummaryEntrySchema = z.object({
  currency: z.string().nullable(),
  openOpportunityCount: z.coerce.number().int().nonnegative(),
  weightedValueTotal: z.coerce.number().nullable(),
  valueMasked: z.boolean(),
});
export type ForecastSummaryEntry = z.infer<typeof ForecastSummaryEntrySchema>;

export function parseForecastSummaryEntry(row: Record<string, unknown>): ForecastSummaryEntry {
  return ForecastSummaryEntrySchema.parse({
    currency: row.currency,
    openOpportunityCount: row.open_opportunity_count,
    weightedValueTotal: row.weighted_value_total,
    valueMasked: row.value_masked,
  });
}
