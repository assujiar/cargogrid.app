/**
 * Expiry and Fraud Prevention mutation primitives (CPL-322, CG-S13-CPL-024).
 * Thin, typed wrappers around every write RPC in supabase/migrations/
 * 20260801240000_create_customer_portal_loyalty_expiry_fraud_prevention.sql.
 *
 * All ten mutations here are staff-only (LYL:Edit/LYL:Configure) -- this
 * checkpoint adds zero new customer-initiated write (the one customer-facing
 * surface, account hold status, is read-only; see server/queries/customer-
 * portal-loyalty-expiry-fraud.ts).
 *
 * Mirrors server/mutations/customer-portal-loyalty-redemptions.ts's own
 * known-error-code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyExpiryRun,
  parseLoyaltyFraudReviewCase,
  parseLoyaltyFraudReviewSuppression,
  RunLoyaltyExpirySweepInputSchema,
  OpenLoyaltyFraudReviewCaseInputSchema,
  ClaimLoyaltyFraudReviewCaseInputSchema,
  DecideLoyaltyFraudReviewCaseInputSchema,
  SuppressLoyaltyFraudReviewInputSchema,
  RevokeLoyaltyFraudReviewSuppressionInputSchema,
  type RunLoyaltyExpirySweepInput,
  type OpenLoyaltyFraudReviewCaseInput,
  type ClaimLoyaltyFraudReviewCaseInput,
  type DecideLoyaltyFraudReviewCaseInput,
  type SuppressLoyaltyFraudReviewInput,
  type RevokeLoyaltyFraudReviewSuppressionInput,
  type LoyaltyExpiryRun,
  type LoyaltyFraudReviewCase,
  type LoyaltyFraudReviewSuppression,
} from "../contracts/customer-portal-loyalty-expiry-fraud/customer-portal-loyalty-expiry-fraud.ts";

export type LoyaltyExpiryFraudMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_EXPIRY_FRAUD_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_idempotency_key",
  "idempotency_key_conflict",
  "invalid_period",
  "loyalty_account_not_found",
  "loyalty_fraud_review_case_not_found",
  "loyalty_fraud_review_suppression_not_found",
  "invalid_risk_signal_type",
  "risk_signal_detail_required",
  "fraud_review_case_already_active",
  "fraud_review_suppressed",
  "fraud_review_already_suppressed",
  "invalid_decision",
  "invalid_transition",
  "reason_required",
  "invalid_expiry",
  "stale_version",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyExpiryFraudMutationErrorCode = (typeof LOYALTY_EXPIRY_FRAUD_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyExpiryFraudMutationErrorCode = KnownLoyaltyExpiryFraudMutationErrorCode | "mutation_failed";

export class LoyaltyExpiryFraudMutationError extends Error {
  readonly code: LoyaltyExpiryFraudMutationErrorCode;

  constructor(code: LoyaltyExpiryFraudMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyExpiryFraudMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyExpiryFraudMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_EXPIRY_FRAUD_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyExpiryFraudMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LoyaltyExpiryFraudMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyExpiryFraudMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyExpiryFraudMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

// ===========================================================================
// Part A: expiry sweep (staff/system, LYL:Edit)
// ===========================================================================

/** Storm-controlled: idempotent per (tenant, runLabel) -- runLabel defaults to the calendar day of asOf. */
export async function runLoyaltyExpirySweep(client: LoyaltyExpiryFraudMutationRpcClient, input: RunLoyaltyExpirySweepInput): Promise<LoyaltyExpiryRun> {
  const v = RunLoyaltyExpirySweepInputSchema.parse(input);
  return callRpc(
    client,
    "run_loyalty_expiry_sweep",
    {
      p_tenant_id: v.tenantId,
      p_as_of: v.asOf,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
      p_run_label: v.runLabel,
    },
    parseLoyaltyExpiryRun,
  );
}

// ===========================================================================
// Part B: fraud review case lifecycle
// ===========================================================================

/** Staff, LYL:Configure -- opens a case AND applies a provisional account hold (composing app.hold_loyalty_account_tier_benefits). */
export async function openLoyaltyFraudReviewCase(client: LoyaltyExpiryFraudMutationRpcClient, input: OpenLoyaltyFraudReviewCaseInput): Promise<LoyaltyFraudReviewCase> {
  const v = OpenLoyaltyFraudReviewCaseInputSchema.parse(input);
  return callRpc(
    client,
    "open_loyalty_fraud_review_case",
    {
      p_tenant_id: v.tenantId,
      p_loyalty_account_id: v.loyaltyAccountId,
      p_risk_signal_type: v.riskSignalType,
      p_risk_signal_detail: v.riskSignalDetail,
      p_idempotency_key: v.idempotencyKey,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyFraudReviewCase,
  );
}

/** Staff, LYL:Edit -- open -> under_review, an optional "I'm reviewing this" claim, never required before deciding. */
export async function claimLoyaltyFraudReviewCase(client: LoyaltyExpiryFraudMutationRpcClient, input: ClaimLoyaltyFraudReviewCaseInput): Promise<LoyaltyFraudReviewCase> {
  const v = ClaimLoyaltyFraudReviewCaseInputSchema.parse(input);
  return callRpc(
    client,
    "claim_loyalty_fraud_review_case",
    {
      p_tenant_id: v.tenantId,
      p_case_id: v.caseId,
      p_expected_version: v.expectedVersion,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyFraudReviewCase,
  );
}

/** Staff, LYL:Configure (governance-grade) -- mandatory non-empty reviewReason. confirm keeps the hold; clear releases it. */
export async function decideLoyaltyFraudReviewCase(client: LoyaltyExpiryFraudMutationRpcClient, input: DecideLoyaltyFraudReviewCaseInput): Promise<LoyaltyFraudReviewCase> {
  const v = DecideLoyaltyFraudReviewCaseInputSchema.parse(input);
  return callRpc(
    client,
    "decide_loyalty_fraud_review_case",
    {
      p_tenant_id: v.tenantId,
      p_case_id: v.caseId,
      p_expected_version: v.expectedVersion,
      p_decision: v.decision,
      p_review_reason: v.reviewReason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyFraudReviewCase,
  );
}

// ===========================================================================
// Part B: suppression/cooldown
// ===========================================================================

/** Staff, LYL:Configure -- mandatory non-empty reason + future expiresAt. At most one active suppression per account. */
export async function suppressLoyaltyFraudReview(client: LoyaltyExpiryFraudMutationRpcClient, input: SuppressLoyaltyFraudReviewInput): Promise<LoyaltyFraudReviewSuppression> {
  const v = SuppressLoyaltyFraudReviewInputSchema.parse(input);
  return callRpc(
    client,
    "suppress_loyalty_fraud_review",
    {
      p_tenant_id: v.tenantId,
      p_loyalty_account_id: v.loyaltyAccountId,
      p_reason: v.reason,
      p_expires_at: v.expiresAt,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyFraudReviewSuppression,
  );
}

/** Staff, LYL:Configure -- idempotent (revoking an already-revoked suppression is a safe no-op). */
export async function revokeLoyaltyFraudReviewSuppression(client: LoyaltyExpiryFraudMutationRpcClient, input: RevokeLoyaltyFraudReviewSuppressionInput): Promise<LoyaltyFraudReviewSuppression> {
  const v = RevokeLoyaltyFraudReviewSuppressionInputSchema.parse(input);
  return callRpc(
    client,
    "revoke_loyalty_fraud_review_suppression",
    {
      p_tenant_id: v.tenantId,
      p_suppression_id: v.suppressionId,
      p_expected_version: v.expectedVersion,
      p_reason: v.reason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyFraudReviewSuppression,
  );
}
