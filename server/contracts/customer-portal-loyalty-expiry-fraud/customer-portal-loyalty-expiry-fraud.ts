/**
 * Expiry and Fraud Prevention contract (CPL-322, CG-S13-CPL-024). Mirrors
 * supabase/migrations/20260801240000_create_customer_portal_loyalty_expiry_
 * fraud_prevention.sql's own two RPC surfaces: (a) tenant-internal,
 * staff-gated (LYL:*) expiry-sweep trigger/history and fraud review-case
 * workbench reads/mutations; and (b) the ONE customer-facing (Layer 4)
 * read, a generic account hold-status projection.
 *
 * Folds BOTH Part A (expiry orchestration) and Part B (fraud hold/review/
 * suppression) into one contract module (this checkpoint's own disclosed
 * call, per the orchestrating task's own "fold into one contract module,
 * your call" latitude) -- one migration, one checkpoint, tightly related.
 *
 * The SEVENTH Loyalty-domain contract in this repository (ADR-0024 Part D).
 */

import { z } from "zod";

// ===========================================================================
// Part A: Expiry orchestration
// ===========================================================================

export const LOYALTY_EXPIRY_RUN_STATUSES = ["pending", "in_progress", "cancelling", "cancelled", "completed", "failed", "dead_letter"] as const;
export const LoyaltyExpiryRunStatusSchema = z.enum(LOYALTY_EXPIRY_RUN_STATUSES);
export type LoyaltyExpiryRunStatus = z.infer<typeof LoyaltyExpiryRunStatusSchema>;

export const LoyaltyExpiryRunSchema = z.object({
  jobId: z.string().uuid(),
  status: LoyaltyExpiryRunStatusSchema,
  runLabel: z.string().nullable(),
  asOf: z.string().nullable(),
  lotsExpiredCount: z.number().int(),
  entitlementsExpiredCount: z.number().int(),
  error: z.string().nullable(),
  createdAt: z.string(),
  completedAt: z.string().nullable(),
  updatedAt: z.string(),
});
export type LoyaltyExpiryRun = z.infer<typeof LoyaltyExpiryRunSchema>;

export function parseLoyaltyExpiryRun(row: Record<string, unknown>): LoyaltyExpiryRun {
  return LoyaltyExpiryRunSchema.parse({
    jobId: row.job_id,
    status: row.status,
    runLabel: (row.run_label as string | null) ?? null,
    asOf: (row.as_of as string | null) ?? null,
    lotsExpiredCount: row.lots_expired_count,
    entitlementsExpiredCount: row.entitlements_expired_count,
    error: (row.error as string | null) ?? null,
    createdAt: row.created_at,
    completedAt: (row.completed_at as string | null) ?? null,
    updatedAt: row.updated_at,
  });
}

export const RunLoyaltyExpirySweepInputSchema = z.object({
  tenantId: z.string().uuid(),
  asOf: z.string().nullable().default(null),
  runLabel: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RunLoyaltyExpirySweepInput = z.input<typeof RunLoyaltyExpirySweepInputSchema>;

// ===========================================================================
// Part B: Fraud review cases
// ===========================================================================

export const LOYALTY_FRAUD_RISK_SIGNAL_TYPES = ["velocity_anomaly", "duplicate_device", "manual_flag", "other"] as const;
export const LoyaltyFraudRiskSignalTypeSchema = z.enum(LOYALTY_FRAUD_RISK_SIGNAL_TYPES);
export type LoyaltyFraudRiskSignalType = z.infer<typeof LoyaltyFraudRiskSignalTypeSchema>;

export const LOYALTY_FRAUD_REVIEW_CASE_STATUSES = ["open", "under_review", "confirmed", "cleared"] as const;
export const LoyaltyFraudReviewCaseStatusSchema = z.enum(LOYALTY_FRAUD_REVIEW_CASE_STATUSES);
export type LoyaltyFraudReviewCaseStatus = z.infer<typeof LoyaltyFraudReviewCaseStatusSchema>;

/** Staff-only, LYL:View-gated -- carries risk_signal_type/risk_signal_detail/review_reason, restricted internal data (business rule). Never parsed/rendered on any customer-facing surface. */
export const LoyaltyFraudReviewCaseSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  riskSignalType: LoyaltyFraudRiskSignalTypeSchema,
  riskSignalDetail: z.string(),
  status: LoyaltyFraudReviewCaseStatusSchema,
  openedBy: z.string().nullable(),
  reviewedBy: z.string().nullable(),
  reviewReason: z.string().nullable(),
  decidedAt: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type LoyaltyFraudReviewCase = z.infer<typeof LoyaltyFraudReviewCaseSchema>;

export function parseLoyaltyFraudReviewCase(row: Record<string, unknown>): LoyaltyFraudReviewCase {
  return LoyaltyFraudReviewCaseSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    riskSignalType: row.risk_signal_type,
    riskSignalDetail: row.risk_signal_detail,
    status: row.status,
    openedBy: (row.opened_by as string | null) ?? null,
    reviewedBy: (row.reviewed_by as string | null) ?? null,
    reviewReason: (row.review_reason as string | null) ?? null,
    decidedAt: (row.decided_at as string | null) ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const OpenLoyaltyFraudReviewCaseInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  riskSignalType: LoyaltyFraudRiskSignalTypeSchema,
  riskSignalDetail: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type OpenLoyaltyFraudReviewCaseInput = z.input<typeof OpenLoyaltyFraudReviewCaseInputSchema>;

export const ClaimLoyaltyFraudReviewCaseInputSchema = z.object({
  tenantId: z.string().uuid(),
  caseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ClaimLoyaltyFraudReviewCaseInput = z.input<typeof ClaimLoyaltyFraudReviewCaseInputSchema>;

export const DecideLoyaltyFraudReviewCaseInputSchema = z.object({
  tenantId: z.string().uuid(),
  caseId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["confirm", "clear"]),
  reviewReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideLoyaltyFraudReviewCaseInput = z.input<typeof DecideLoyaltyFraudReviewCaseInputSchema>;

// ===========================================================================
// Part B: Suppression/cooldown
// ===========================================================================

export const LoyaltyFraudReviewSuppressionSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  reason: z.string(),
  expiresAt: z.string(),
  suppressedByAuthUserId: z.string().uuid(),
  suppressedBy: z.string().nullable(),
  revokedAt: z.string().nullable(),
  revokedBy: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type LoyaltyFraudReviewSuppression = z.infer<typeof LoyaltyFraudReviewSuppressionSchema>;

export function parseLoyaltyFraudReviewSuppression(row: Record<string, unknown>): LoyaltyFraudReviewSuppression {
  return LoyaltyFraudReviewSuppressionSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    loyaltyAccountId: row.loyalty_account_id,
    reason: row.reason,
    expiresAt: row.expires_at,
    suppressedByAuthUserId: row.suppressed_by_auth_user_id,
    suppressedBy: (row.suppressed_by as string | null) ?? null,
    revokedAt: (row.revoked_at as string | null) ?? null,
    revokedBy: (row.revoked_by as string | null) ?? null,
    revokedReason: (row.revoked_reason as string | null) ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const SuppressLoyaltyFraudReviewInputSchema = z.object({
  tenantId: z.string().uuid(),
  loyaltyAccountId: z.string().uuid(),
  reason: z.string().min(1),
  expiresAt: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SuppressLoyaltyFraudReviewInput = z.input<typeof SuppressLoyaltyFraudReviewInputSchema>;

export const RevokeLoyaltyFraudReviewSuppressionInputSchema = z.object({
  tenantId: z.string().uuid(),
  suppressionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RevokeLoyaltyFraudReviewSuppressionInput = z.input<typeof RevokeLoyaltyFraudReviewSuppressionInputSchema>;

// ===========================================================================
// Cursor pagination
// ===========================================================================

export const LoyaltyExpiryFraudUpdatedAtCursorSchema = z
  .object({
    cursorUpdatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorUpdatedAt, {
    message: "cursorUpdatedAt is required when cursorId is supplied",
    path: ["cursorUpdatedAt"],
  });
export type LoyaltyExpiryFraudUpdatedAtCursor = z.input<typeof LoyaltyExpiryFraudUpdatedAtCursorSchema>;

export const LoyaltyExpiryFraudCreatedAtCursorSchema = z
  .object({
    cursorCreatedAt: z.string().nullable().optional(),
    cursorId: z.string().uuid().nullable().optional(),
  })
  .refine((cursor) => !cursor.cursorId || !!cursor.cursorCreatedAt, {
    message: "cursorCreatedAt is required when cursorId is supplied",
    path: ["cursorCreatedAt"],
  });
export type LoyaltyExpiryFraudCreatedAtCursor = z.input<typeof LoyaltyExpiryFraudCreatedAtCursorSchema>;

// ===========================================================================
// Customer-facing (Layer 4, ADR-0024 Part A) -- ONLY is_on_hold/hold_notice,
// structurally never risk_signal_type/risk_signal_detail/review_reason/
// reviewed_by (business rule: "restricted internal data... never exposed to
// a customer_user caller, not even in an error message").
// ===========================================================================

export const CustomerPortalLoyaltyAccountHoldStatusSchema = z.object({
  loyaltyAccountId: z.string().uuid(),
  programName: z.string(),
  isOnHold: z.boolean(),
  holdNotice: z.string().nullable(),
});
export type CustomerPortalLoyaltyAccountHoldStatus = z.infer<typeof CustomerPortalLoyaltyAccountHoldStatusSchema>;

export function parseCustomerPortalLoyaltyAccountHoldStatus(row: Record<string, unknown>): CustomerPortalLoyaltyAccountHoldStatus {
  return CustomerPortalLoyaltyAccountHoldStatusSchema.parse({
    loyaltyAccountId: row.loyalty_account_id,
    programName: row.program_name,
    isOnHold: row.is_on_hold,
    holdNotice: (row.hold_notice as string | null) ?? null,
  });
}

/** Customer-safe, plain-language status label -- never the raw enum value verbatim. */
export function describeLoyaltyFraudReviewCaseStatus(status: LoyaltyFraudReviewCaseStatus): string {
  switch (status) {
    case "open":
      return "Open";
    case "under_review":
      return "Under review";
    case "confirmed":
      return "Confirmed";
    case "cleared":
      return "Cleared";
    default:
      return status;
  }
}
