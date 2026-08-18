/**
 * Redemption Approval and Fulfillment mutation primitives (CPL-321,
 * CG-S13-CPL-023). Thin, typed wrappers around every write RPC in
 * supabase/migrations/20260801230000_create_customer_portal_loyalty_
 * redemption_approval_fulfillment.sql.
 *
 * app.submit_loyalty_redemption/app.cancel_loyalty_redemption are dual
 * authority (customer_user own account scope OR staff LYL:Edit) -- see the
 * migration's own design decision 5 for the full, disclosed reasoning
 * behind why a genuine, unassisted customer submission may gracefully land
 * pending_approval even for an "auto-approve-eligible" discount_voucher
 * reward. app.decide_loyalty_redemption/app.mark_loyalty_redemption_
 * fulfilled/app.mark_loyalty_redemption_fulfillment_failed are staff-only.
 *
 * Mirrors server/mutations/customer-portal-loyalty-rewards.ts's own
 * known-error-code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyRedemption,
  SubmitLoyaltyRedemptionInputSchema,
  DecideLoyaltyRedemptionInputSchema,
  CancelLoyaltyRedemptionInputSchema,
  MarkLoyaltyRedemptionFulfilledInputSchema,
  MarkLoyaltyRedemptionFulfillmentFailedInputSchema,
  type SubmitLoyaltyRedemptionInput,
  type DecideLoyaltyRedemptionInput,
  type CancelLoyaltyRedemptionInput,
  type MarkLoyaltyRedemptionFulfilledInput,
  type MarkLoyaltyRedemptionFulfillmentFailedInput,
  type LoyaltyRedemption,
} from "../contracts/customer-portal-loyalty-redemptions/customer-portal-loyalty-redemptions.ts";

export type LoyaltyRedemptionMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_REDEMPTION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_idempotency_key",
  "idempotency_key_conflict",
  "loyalty_account_not_found",
  "loyalty_reward_not_found",
  "loyalty_redemption_not_found",
  "reward_not_currently_redeemable",
  "reward_redemption_unavailable",
  "account_on_hold",
  "ineligible_reward",
  "invalid_decision",
  "reason_required",
  "invalid_transition",
  "stale_version",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyRedemptionMutationErrorCode = (typeof LOYALTY_REDEMPTION_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyRedemptionMutationErrorCode = KnownLoyaltyRedemptionMutationErrorCode | "mutation_failed";

export class LoyaltyRedemptionMutationError extends Error {
  readonly code: LoyaltyRedemptionMutationErrorCode;

  constructor(code: LoyaltyRedemptionMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyRedemptionMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyRedemptionMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_REDEMPTION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyRedemptionMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: LoyaltyRedemptionMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<LoyaltyRedemption> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyRedemptionMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyRedemptionMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseLoyaltyRedemption(row as Record<string, unknown>);
}

// ===========================================================================
// Main flow: submit (dual authority) -> decide (staff) -> mark fulfilled/
// failed (staff, physical_item/service_credit only)
// ===========================================================================

/** Dual authority (customer own account scope OR staff LYL:Edit). Idempotent on (tenantId, idempotencyKey). */
export async function submitLoyaltyRedemption(client: LoyaltyRedemptionMutationRpcClient, input: SubmitLoyaltyRedemptionInput): Promise<LoyaltyRedemption> {
  const v = SubmitLoyaltyRedemptionInputSchema.parse(input);
  return callRpc(client, "submit_loyalty_redemption", {
    p_tenant_id: v.tenantId,
    p_loyalty_account_id: v.loyaltyAccountId,
    p_reward_id: v.rewardId,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Staff-only, LYL:Configure -- structurally unreachable by any customer_user identity. Mandatory non-empty reason on reject. */
export async function decideLoyaltyRedemption(client: LoyaltyRedemptionMutationRpcClient, input: DecideLoyaltyRedemptionInput): Promise<LoyaltyRedemption> {
  const v = DecideLoyaltyRedemptionInputSchema.parse(input);
  return callRpc(client, "decide_loyalty_redemption", {
    p_tenant_id: v.tenantId,
    p_redemption_id: v.redemptionId,
    p_expected_version: v.expectedVersion,
    p_decision: v.decision,
    p_decision_reason: v.decisionReason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Dual authority, same gate as submit. Only a still-pending (pending_approval) redemption may be cancelled. */
export async function cancelLoyaltyRedemption(client: LoyaltyRedemptionMutationRpcClient, input: CancelLoyaltyRedemptionInput): Promise<LoyaltyRedemption> {
  const v = CancelLoyaltyRedemptionInputSchema.parse(input);
  return callRpc(client, "cancel_loyalty_redemption", {
    p_tenant_id: v.tenantId,
    p_redemption_id: v.redemptionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Staff, LYL:Edit. physical_item/service_credit only -- discount_voucher is already fulfilled at approval. */
export async function markLoyaltyRedemptionFulfilled(client: LoyaltyRedemptionMutationRpcClient, input: MarkLoyaltyRedemptionFulfilledInput): Promise<LoyaltyRedemption> {
  const v = MarkLoyaltyRedemptionFulfilledInputSchema.parse(input);
  return callRpc(client, "mark_loyalty_redemption_fulfilled", {
    p_tenant_id: v.tenantId,
    p_redemption_id: v.redemptionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Staff, LYL:Edit. Mandatory non-empty reason -- genuinely reverses the stock reservation and point consumption made at approval time. */
export async function markLoyaltyRedemptionFulfillmentFailed(client: LoyaltyRedemptionMutationRpcClient, input: MarkLoyaltyRedemptionFulfillmentFailedInput): Promise<LoyaltyRedemption> {
  const v = MarkLoyaltyRedemptionFulfillmentFailedInputSchema.parse(input);
  return callRpc(client, "mark_loyalty_redemption_fulfillment_failed", {
    p_tenant_id: v.tenantId,
    p_redemption_id: v.redemptionId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
