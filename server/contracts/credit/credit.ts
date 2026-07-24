/**
 * Credit and Commercial Control contract (COM-157, CG-S7-COM-016). Mirrors
 * supabase/migrations/20260724310000_create_commercial_credit_commercial_control.sql's
 * app.credit_profiles/app.credit_profile_overrides/app.credit_check_snapshots shape and
 * the request/decide/hold/release/override/check RPCs.
 *
 * Every money-bearing figure (limit amounts, override amount, check requested/effective
 * amounts) is masked (COM:View selling price, reused -- see the migration's own header)
 * on every read path this contract's parsers cover -- either via a `*_directory` view or,
 * for `check_customer_credit`, the RPC's own masked return shape. `amountMasked` is a
 * real, always-present boolean field, never inferred from a null value alone.
 */

import { z } from "zod";

export const CREDIT_PROFILE_STATUSES = ["requested", "active", "held", "expired", "rejected"] as const;
export const CreditProfileStatusSchema = z.enum(CREDIT_PROFILE_STATUSES);
export type CreditProfileStatus = z.infer<typeof CreditProfileStatusSchema>;

export const CREDIT_CHECK_OUTCOMES = ["allow", "blocked_no_profile", "blocked_not_active", "blocked_hold", "blocked_currency_mismatch", "blocked_limit"] as const;
export const CreditCheckOutcomeSchema = z.enum(CREDIT_CHECK_OUTCOMES);
export type CreditCheckOutcome = z.infer<typeof CreditCheckOutcomeSchema>;

/** Maps app.credit_profiles_directory's own masked row. */
export const CreditProfileSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  currency: z.string().nullable(),
  requestedLimitAmount: z.coerce.number().nullable(),
  approvedLimitAmount: z.coerce.number().nullable(),
  amountMasked: z.boolean(),
  status: CreditProfileStatusSchema,
  effectiveFrom: z.string().nullable(),
  effectiveTo: z.string().nullable(),
  holdReason: z.string().nullable(),
  rejectedReason: z.string().nullable(),
  approvalRequestId: z.string().uuid().nullable(),
  supersedesProfileId: z.string().uuid().nullable(),
  approvedBy: z.string().nullable(),
  approvedAt: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type CreditProfile = z.infer<typeof CreditProfileSchema>;

export function parseCreditProfile(row: Record<string, unknown>): CreditProfile {
  return CreditProfileSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    accountId: row.account_id,
    currency: row.currency,
    requestedLimitAmount: row.requested_limit_amount,
    approvedLimitAmount: row.approved_limit_amount,
    amountMasked: row.amount_masked,
    status: row.status,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to,
    holdReason: row.hold_reason,
    rejectedReason: row.rejected_reason,
    approvalRequestId: row.approval_request_id,
    supersedesProfileId: row.supersedes_profile_id,
    approvedBy: row.approved_by,
    approvedAt: row.approved_at,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Maps app.credit_profile_overrides_directory's own masked row. */
export const CreditProfileOverrideSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  creditProfileId: z.string().uuid(),
  amount: z.coerce.number().nullable(),
  amountMasked: z.boolean(),
  reason: z.string(),
  expiresAt: z.string(),
  approvedBy: z.string().nullable(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
});
export type CreditProfileOverride = z.infer<typeof CreditProfileOverrideSchema>;

export function parseCreditProfileOverride(row: Record<string, unknown>): CreditProfileOverride {
  return CreditProfileOverrideSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    creditProfileId: row.credit_profile_id,
    amount: row.amount,
    amountMasked: row.amount_masked,
    reason: row.reason,
    expiresAt: row.expires_at,
    approvedBy: row.approved_by,
    createdBy: row.created_by,
    createdAt: row.created_at,
  });
}

/** Maps app.check_customer_credit()'s own masked return row -- never the raw app.credit_check_snapshots row. */
export const CreditCheckResultSchema = z.object({
  id: z.string().uuid(),
  creditProfileId: z.string().uuid().nullable(),
  profileStatusAtCheck: CreditProfileStatusSchema.nullable(),
  currency: z.string().nullable(),
  requestedAmount: z.coerce.number().nullable(),
  effectiveLimitAmount: z.coerce.number().nullable(),
  amountMasked: z.boolean(),
  outcome: CreditCheckOutcomeSchema,
  checkedAt: z.string(),
});
export type CreditCheckResult = z.infer<typeof CreditCheckResultSchema>;

export function parseCreditCheckResult(row: Record<string, unknown>): CreditCheckResult {
  return CreditCheckResultSchema.parse({
    id: row.id,
    creditProfileId: row.credit_profile_id,
    profileStatusAtCheck: row.profile_status_at_check,
    currency: row.currency,
    requestedAmount: row.requested_amount,
    effectiveLimitAmount: row.effective_limit_amount,
    amountMasked: row.amount_masked,
    outcome: row.outcome,
    checkedAt: row.checked_at,
  });
}

export const RequestCustomerCreditProfileInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  requestedLimitAmount: z.number().nonnegative(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RequestCustomerCreditProfileInput = z.input<typeof RequestCustomerCreditProfileInputSchema>;

/** reauthConfirmedAt must be within the last 5 minutes (app.decide_credit_profile_approval_step's own server-side freshness check, reused from PLT-115) -- Prompt 157 §16's MFA-for-privileged-approvers gate; see the migration header for the disclosed boundary (no live MFA challenge UI exists yet). */
export const DecideCreditProfileApprovalStepInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  reason: z.string().nullable().default(null),
  reauthConfirmedAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type DecideCreditProfileApprovalStepInput = z.input<typeof DecideCreditProfileApprovalStepInputSchema>;

export const HoldCreditProfileInputSchema = z.object({
  profileId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  reauthConfirmedAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type HoldCreditProfileInput = z.input<typeof HoldCreditProfileInputSchema>;

export const ReleaseCreditProfileInputSchema = z.object({
  profileId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reauthConfirmedAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReleaseCreditProfileInput = z.input<typeof ReleaseCreditProfileInputSchema>;

export const CreateCreditOverrideInputSchema = z.object({
  profileId: z.string().uuid(),
  amount: z.number().nonnegative(),
  reason: z.string().min(1),
  expiresAt: z.string(),
  reauthConfirmedAt: z.string(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateCreditOverrideInput = z.input<typeof CreateCreditOverrideInputSchema>;

export const CheckCustomerCreditInputSchema = z.object({
  tenantId: z.string().uuid(),
  accountId: z.string().uuid(),
  currency: z.string().regex(/^[A-Z]{3}$/),
  requestedAmount: z.number().nonnegative(),
  contextType: z.string().nullable().default(null),
  contextId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CheckCustomerCreditInput = z.input<typeof CheckCustomerCreditInputSchema>;
