/**
 * Liability Reconciliation Analytics contract (CPL-323, CG-S13-CPL-025).
 * Mirrors supabase/migrations/20260801250000_create_customer_portal_
 * loyalty_liability_reconciliation_analytics.sql's own RPC surface: the
 * tenant-internal, staff-gated (LYL:*) execute/resolve/certify reconciliation
 * workflow and its own run/exception reads, the staff-gated engagement-
 * metrics read, and the ONE customer-facing (Layer 4) consolidated loyalty
 * summary read.
 *
 * The EIGHTH Loyalty-domain contract in this repository (ADR-0024 Part D).
 */

import { z } from "zod";

// ===========================================================================
// Reconciliation runs
// ===========================================================================

export const LOYALTY_LIABILITY_RECONCILIATION_RUN_STATUSES = ["open", "exceptions_pending", "certified"] as const;
export const LoyaltyLiabilityReconciliationRunStatusSchema = z.enum(LOYALTY_LIABILITY_RECONCILIATION_RUN_STATUSES);
export type LoyaltyLiabilityReconciliationRunStatus = z.infer<typeof LoyaltyLiabilityReconciliationRunStatusSchema>;

/**
 * pointsLiabilityTotal is a RAW POINTS total, dimensionless -- never a
 * fabricated points-to-currency conversion (this migration's own disclosed
 * design decision 1: no such conversion rate is configured anywhere in this
 * repository's real Loyalty schema). The other four totals are scoped to
 * this run's own `currency` column (design decision 6).
 */
export const LoyaltyLiabilityReconciliationRunSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  asOf: z.string(),
  currency: z.string().length(3),
  status: LoyaltyLiabilityReconciliationRunStatusSchema,
  pointsLiabilityTotal: z.number(),
  cashbackLiabilityTotal: z.number(),
  discountLiabilityTotal: z.number(),
  voucherLiabilityTotal: z.number(),
  rewardFulfillmentLiabilityTotal: z.number(),
  computedAt: z.string(),
  configVersion: z.number().int().positive(),
  idempotencyKey: z.string(),
  executedBy: z.string().nullable(),
  certifiedBy: z.string().nullable(),
  certifiedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyLiabilityReconciliationRun = z.infer<typeof LoyaltyLiabilityReconciliationRunSchema>;

export function parseLoyaltyLiabilityReconciliationRun(row: Record<string, unknown>): LoyaltyLiabilityReconciliationRun {
  return LoyaltyLiabilityReconciliationRunSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    asOf: row.as_of,
    currency: row.currency,
    status: row.status,
    pointsLiabilityTotal: Number(row.points_liability_total),
    cashbackLiabilityTotal: Number(row.cashback_liability_total),
    discountLiabilityTotal: Number(row.discount_liability_total),
    voucherLiabilityTotal: Number(row.voucher_liability_total),
    rewardFulfillmentLiabilityTotal: Number(row.reward_fulfillment_liability_total),
    computedAt: row.computed_at,
    configVersion: row.config_version,
    idempotencyKey: row.idempotency_key,
    executedBy: (row.executed_by as string | null) ?? null,
    certifiedBy: (row.certified_by as string | null) ?? null,
    certifiedAt: (row.certified_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/**
 * tenantId/currency/actor fields required; asOf/idempotencyKey/configVersion
 * optional -- p_as_of defaults server-side to clock_timestamp(), the
 * idempotency key defaults to a calendar-day-and-currency-derived key
 * (mirrors CPL-322's own run_label-defaulting precedent), configVersion
 * defaults to 1 (no persisted, versionable liability-computation config
 * exists yet, mirrors CPL-318's own identical precedent).
 */
export const ExecuteLoyaltyLiabilityReconciliationRunInputSchema = z.object({
  tenantId: z.string().uuid(),
  currency: z.string().length(3),
  asOf: z.string().nullable().default(null),
  idempotencyKey: z.string().nullable().default(null),
  configVersion: z.number().int().positive().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ExecuteLoyaltyLiabilityReconciliationRunInput = z.input<typeof ExecuteLoyaltyLiabilityReconciliationRunInputSchema>;

export const CertifyLoyaltyLiabilityReconciliationRunInputSchema = z.object({
  tenantId: z.string().uuid(),
  runId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CertifyLoyaltyLiabilityReconciliationRunInput = z.input<typeof CertifyLoyaltyLiabilityReconciliationRunInputSchema>;

// ===========================================================================
// Reconciliation exceptions
// ===========================================================================

// Tier C review fix (Batch 5 close): added redemption_liability_status_mismatch
// -- the reward-fulfillment liability line's own status is now independently
// re-derived from app.loyalty_redemption_events, mirroring the entitlement
// line's own derivation exactly, so it can now raise the same class of
// exception on a cached/re-derived status mismatch.
export const LOYALTY_LIABILITY_RECONCILIATION_EXCEPTION_TYPES = ["point_balance_derivation_mismatch", "entitlement_state_derivation_mismatch", "redemption_liability_status_mismatch"] as const;
export const LoyaltyLiabilityReconciliationExceptionTypeSchema = z.enum(LOYALTY_LIABILITY_RECONCILIATION_EXCEPTION_TYPES);
export type LoyaltyLiabilityReconciliationExceptionType = z.infer<typeof LoyaltyLiabilityReconciliationExceptionTypeSchema>;

export const LOYALTY_LIABILITY_RECONCILIATION_EXCEPTION_STATUSES = ["open", "resolved"] as const;
export const LoyaltyLiabilityReconciliationExceptionStatusSchema = z.enum(LOYALTY_LIABILITY_RECONCILIATION_EXCEPTION_STATUSES);
export type LoyaltyLiabilityReconciliationExceptionStatus = z.infer<typeof LoyaltyLiabilityReconciliationExceptionStatusSchema>;

/**
 * detail is a jsonb blob whose shape depends on exceptionType (this
 * migration's own disclosed choice over separate expected_value/
 * actual_value columns, since the three exception types carry structurally
 * different detail shapes) -- kept as a loosely-typed record here rather
 * than a discriminated union, since the UI only ever renders it read-only.
 */
export const LoyaltyLiabilityReconciliationExceptionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  runId: z.string().uuid(),
  exceptionType: LoyaltyLiabilityReconciliationExceptionTypeSchema,
  detail: z.record(z.string(), z.unknown()),
  status: LoyaltyLiabilityReconciliationExceptionStatusSchema,
  resolvedBy: z.string().nullable(),
  resolutionReason: z.string().nullable(),
  resolvedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyLiabilityReconciliationException = z.infer<typeof LoyaltyLiabilityReconciliationExceptionSchema>;

export function parseLoyaltyLiabilityReconciliationException(row: Record<string, unknown>): LoyaltyLiabilityReconciliationException {
  return LoyaltyLiabilityReconciliationExceptionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    runId: row.run_id,
    exceptionType: row.exception_type,
    detail: (row.detail as Record<string, unknown> | null) ?? {},
    status: row.status,
    resolvedBy: (row.resolved_by as string | null) ?? null,
    resolutionReason: (row.resolution_reason as string | null) ?? null,
    resolvedAt: (row.resolved_at as string | null) ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const ResolveLoyaltyLiabilityReconciliationExceptionInputSchema = z.object({
  tenantId: z.string().uuid(),
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  resolutionReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ResolveLoyaltyLiabilityReconciliationExceptionInput = z.input<typeof ResolveLoyaltyLiabilityReconciliationExceptionInputSchema>;

// ===========================================================================
// Cursor pagination
// ===========================================================================

export const LoyaltyLiabilityUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyLiabilityUpdatedAtCursor = z.input<typeof LoyaltyLiabilityUpdatedAtCursorSchema>;

// ===========================================================================
// Engagement metrics (staff, LYL:View -- Step-13-scope basic analytics only,
// aggregate/tenant-wide, never a per-customer breakdown or internal_cost/
// vendor_ref/margin).
// ===========================================================================

export const LoyaltyEngagementMetricsSchema = z.object({
  periodStart: z.string(),
  periodEnd: z.string(),
  activeLoyaltyAccountsCount: z.number().int().nonnegative(),
  pointsEarnedTotal: z.number(),
  pointsRedeemedTotal: z.number(),
  redemptionCount: z.number().int().nonnegative(),
  redemptionRate: z.number(),
  publishedRewardCount: z.number().int().nonnegative(),
  rewardsWithRedemptionCount: z.number().int().nonnegative(),
  computedAt: z.string(),
});
export type LoyaltyEngagementMetrics = z.infer<typeof LoyaltyEngagementMetricsSchema>;

export function parseLoyaltyEngagementMetrics(row: Record<string, unknown>): LoyaltyEngagementMetrics {
  return LoyaltyEngagementMetricsSchema.parse({
    periodStart: row.period_start,
    periodEnd: row.period_end,
    activeLoyaltyAccountsCount: row.active_loyalty_accounts_count,
    pointsEarnedTotal: Number(row.points_earned_total),
    pointsRedeemedTotal: Number(row.points_redeemed_total),
    redemptionCount: row.redemption_count,
    redemptionRate: Number(row.redemption_rate),
    publishedRewardCount: row.published_reward_count,
    rewardsWithRedemptionCount: row.rewards_with_redemption_count,
    computedAt: row.computed_at,
  });
}

export const GetLoyaltyEngagementMetricsInputSchema = z.object({
  tenantId: z.string().uuid(),
  periodStart: z.string().min(1),
  periodEnd: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
});
export type GetLoyaltyEngagementMetricsInput = z.input<typeof GetLoyaltyEngagementMetricsInputSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A) -- composes (never duplicates)
// the already-existing per-domain customer reads (CPL-317/318/319/321/322)
// into one consolidated row for the caller's own single loyalty account.
// ===========================================================================

export const LoyaltyActiveEntitlementSummaryLineSchema = z.object({
  benefitType: z.string(),
  currency: z.string(),
  count: z.number().int().nonnegative(),
  total: z.number(),
});
export type LoyaltyActiveEntitlementSummaryLine = z.infer<typeof LoyaltyActiveEntitlementSummaryLineSchema>;

export const LoyaltyRecentRedemptionSummaryLineSchema = z.object({
  redemptionId: z.string().uuid(),
  rewardName: z.string(),
  rewardType: z.string(),
  status: z.string(),
  fulfillmentStatus: z.string(),
  pointsConsumed: z.number(),
  decidedAt: z.string().nullable(),
  createdAt: z.string(),
});
export type LoyaltyRecentRedemptionSummaryLine = z.infer<typeof LoyaltyRecentRedemptionSummaryLineSchema>;

export const CustomerPortalLoyaltySummarySchema = z.object({
  loyaltyAccountId: z.string().uuid(),
  customerAccountId: z.string().uuid(),
  programId: z.string().uuid(),
  programName: z.string().nullable(),
  accountStatus: z.string(),
  enrolledAt: z.string(),
  tierName: z.string().nullable(),
  tierBenefits: z.record(z.string(), z.unknown()),
  isTierBenefitsSuspended: z.boolean(),
  pointsAvailable: z.number(),
  activeEntitlementsCount: z.number().int().nonnegative(),
  activeEntitlementsSummary: z.array(LoyaltyActiveEntitlementSummaryLineSchema),
  recentRedemptions: z.array(LoyaltyRecentRedemptionSummaryLineSchema),
  isOnHold: z.boolean(),
  holdNotice: z.string().nullable(),
  generatedAt: z.string(),
});
export type CustomerPortalLoyaltySummary = z.infer<typeof CustomerPortalLoyaltySummarySchema>;

export function parseCustomerPortalLoyaltySummary(row: Record<string, unknown>): CustomerPortalLoyaltySummary {
  return CustomerPortalLoyaltySummarySchema.parse({
    loyaltyAccountId: row.loyalty_account_id,
    customerAccountId: row.customer_account_id,
    programId: row.program_id,
    programName: (row.program_name as string | null) ?? null,
    accountStatus: row.account_status,
    enrolledAt: row.enrolled_at,
    tierName: (row.tier_name as string | null) ?? null,
    tierBenefits: (row.tier_benefits as Record<string, unknown> | null) ?? {},
    isTierBenefitsSuspended: Boolean(row.is_tier_benefits_suspended),
    pointsAvailable: Number(row.points_available),
    activeEntitlementsCount: row.active_entitlements_count,
    activeEntitlementsSummary: ((row.active_entitlements_summary as unknown[] | null) ?? []).map((line) => {
      const l = line as Record<string, unknown>;
      return { benefitType: l.benefitType as string, currency: l.currency as string, count: l.count as number, total: Number(l.total) };
    }),
    recentRedemptions: ((row.recent_redemptions as unknown[] | null) ?? []).map((line) => {
      const l = line as Record<string, unknown>;
      return {
        redemptionId: l.redemptionId as string,
        rewardName: l.rewardName as string,
        rewardType: l.rewardType as string,
        status: l.status as string,
        fulfillmentStatus: l.fulfillmentStatus as string,
        pointsConsumed: Number(l.pointsConsumed),
        decidedAt: (l.decidedAt as string | null) ?? null,
        createdAt: l.createdAt as string,
      };
    }),
    isOnHold: Boolean(row.is_on_hold),
    holdNotice: (row.hold_notice as string | null) ?? null,
    generatedAt: row.generated_at,
  });
}

export const GetCustomerPortalLoyaltySummaryInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
});
export type GetCustomerPortalLoyaltySummaryInput = z.input<typeof GetCustomerPortalLoyaltySummaryInputSchema>;

/** Staff-facing, plain-language status label -- never the raw enum value verbatim. */
export function describeLoyaltyLiabilityReconciliationRunStatus(status: LoyaltyLiabilityReconciliationRunStatus): string {
  switch (status) {
    case "open":
      return "Ready to certify";
    case "exceptions_pending":
      return "Exceptions pending";
    case "certified":
      return "Certified";
    default:
      return status;
  }
}
