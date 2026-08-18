/**
 * Points Ledger mutation primitives (CPL-318, CG-S13-CPL-020). Thin, typed
 * wrappers around every write RPC in supabase/migrations/20260801200000_
 * create_customer_portal_loyalty_points_ledger.sql -- ALL of them are
 * staff/system-gated (LYL:Edit/Configure) internally by the RPC itself;
 * there is no customer-initiated write in this capability (ADR-0024 Part B).
 * None of these exports should ever be called from a customer-facing Server
 * Action.
 *
 * app.consume_loyalty_points_fifo is wrapped here for completeness/future
 * use but not called from any UI action in this checkpoint -- no reward
 * catalog/redemption capability exists yet to trigger it from (ISS-2026-128).
 *
 * Mirrors server/mutations/customer-portal-loyalty-tier.ts's own known-
 * error-code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyPointLedgerEntry,
  parseLoyaltyPointAdjustmentRequest,
  PostLoyaltyPointsEarnedInputSchema,
  ReverseLoyaltyPointsEarnedInputSchema,
  ExpireLoyaltyPointLotsInputSchema,
  RequestLoyaltyPointAdjustmentInputSchema,
  DecideLoyaltyPointAdjustmentInputSchema,
  type PostLoyaltyPointsEarnedInput,
  type ReverseLoyaltyPointsEarnedInput,
  type ExpireLoyaltyPointLotsInput,
  type RequestLoyaltyPointAdjustmentInput,
  type DecideLoyaltyPointAdjustmentInput,
  type LoyaltyPointLedgerEntry,
  type LoyaltyPointAdjustmentRequest,
} from "../contracts/customer-portal-loyalty-points/customer-portal-loyalty-points.ts";

export type LoyaltyPointsMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_POINTS_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_event_type",
  "invalid_amount",
  "invalid_reason",
  "invalid_idempotency_key",
  "invalid_expiry_days",
  "loyalty_account_not_found",
  "loyalty_point_lot_not_found",
  "loyalty_point_balance_not_found",
  "loyalty_earning_event_not_found",
  "not_a_points_earning_event",
  "earning_event_is_a_reversal",
  "not_a_reversal_earning_event",
  "invalid_earning_event_amount",
  "lot_already_fully_consumed",
  "insufficient_points_balance",
  "insufficient_lot_remaining",
  "reason_required",
  "adjustment_already_pending",
  "idempotency_key_conflict",
  "self_approval_not_allowed",
  "stale_version",
  "invalid_transition",
  "invalid_decision",
  "loyalty_point_adjustment_request_not_found",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyPointsMutationErrorCode = (typeof LOYALTY_POINTS_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyPointsMutationErrorCode = KnownLoyaltyPointsMutationErrorCode | "mutation_failed";

export class LoyaltyPointsMutationError extends Error {
  readonly code: LoyaltyPointsMutationErrorCode;

  constructor(code: LoyaltyPointsMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyPointsMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyPointsMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_POINTS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyPointsMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LoyaltyPointsMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyPointsMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyPointsMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

async function callRpcMany<T>(client: LoyaltyPointsMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T[]> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyPointsMutationError(classifyError(error.message), error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parse);
}

// ===========================================================================
// Earning/reversal (LYL:Edit / LYL:Configure)
// ===========================================================================

/** Idempotent on the underlying earning event -- calling this twice for the same event is a safe no-op, never a duplicate lot or ledger entry. */
export async function postLoyaltyPointsEarned(client: LoyaltyPointsMutationRpcClient, input: PostLoyaltyPointsEarnedInput): Promise<LoyaltyPointLedgerEntry> {
  const v = PostLoyaltyPointsEarnedInputSchema.parse(input);
  return callRpc(
    client,
    "post_loyalty_points_earned",
    {
      p_tenant_id: v.tenantId,
      p_earning_event_id: v.earningEventId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
      p_expiry_days: v.expiryDays,
    },
    parseLoyaltyPointLedgerEntry,
  );
}

/** NEVER deletes or edits the original entry -- inserts a new, linked reversal row. Idempotent on the underlying reversal earning event. */
export async function reverseLoyaltyPointsEarned(client: LoyaltyPointsMutationRpcClient, input: ReverseLoyaltyPointsEarnedInput): Promise<LoyaltyPointLedgerEntry> {
  const v = ReverseLoyaltyPointsEarnedInputSchema.parse(input);
  return callRpc(
    client,
    "reverse_loyalty_points_earned",
    {
      p_tenant_id: v.tenantId,
      p_reversal_earning_event_id: v.reversalEarningEventId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyPointLedgerEntry,
  );
}

/** Scans due lots tenant-wide, posts one expiry entry per lot. Idempotent per lot -- a safe no-op to re-run. */
export async function expireLoyaltyPointLots(client: LoyaltyPointsMutationRpcClient, input: ExpireLoyaltyPointLotsInput): Promise<LoyaltyPointLedgerEntry[]> {
  const v = ExpireLoyaltyPointLotsInputSchema.parse(input);
  return callRpcMany(
    client,
    "expire_loyalty_point_lots",
    {
      p_tenant_id: v.tenantId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyPointLedgerEntry,
  );
}

// ===========================================================================
// FIFO consumption (LYL:Edit) -- a real, complete primitive; no reward
// catalog/redemption UI exists yet to trigger it from (ISS-2026-128).
// ===========================================================================

export interface ConsumeLoyaltyPointsFifoInput {
  readonly tenantId: string;
  readonly loyaltyAccountId: string;
  readonly amount: number;
  readonly sourceType: string;
  readonly sourceId: string;
  readonly idempotencyKey: string;
  readonly actorAuthUserId: string;
  readonly actorLabel: string;
}

export async function consumeLoyaltyPointsFifo(client: LoyaltyPointsMutationRpcClient, input: ConsumeLoyaltyPointsFifoInput): Promise<LoyaltyPointLedgerEntry[]> {
  return callRpcMany(
    client,
    "consume_loyalty_points_fifo",
    {
      p_tenant_id: input.tenantId,
      p_loyalty_account_id: input.loyaltyAccountId,
      p_amount: input.amount,
      p_source_type: input.sourceType,
      p_source_id: input.sourceId,
      p_idempotency_key: input.idempotencyKey,
      p_actor_auth_user_id: input.actorAuthUserId,
      p_actor_label: input.actorLabel,
    },
    parseLoyaltyPointLedgerEntry,
  );
}

// ===========================================================================
// Point adjustment maker-checker (LYL:Edit maker / LYL:Configure checker)
// ===========================================================================

export async function requestLoyaltyPointAdjustment(client: LoyaltyPointsMutationRpcClient, input: RequestLoyaltyPointAdjustmentInput): Promise<LoyaltyPointAdjustmentRequest> {
  const v = RequestLoyaltyPointAdjustmentInputSchema.parse(input);
  return callRpc(
    client,
    "request_loyalty_point_adjustment",
    {
      p_tenant_id: v.tenantId,
      p_loyalty_account_id: v.loyaltyAccountId,
      p_adjustment_amount: v.adjustmentAmount,
      p_reason: v.reason,
      p_idempotency_key: v.idempotencyKey,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyPointAdjustmentRequest,
  );
}

/** Self-approval blocked server-side (self_approval_not_allowed) -- the requester may not also decide their own request. On approval, posts a real adjustment ledger entry in the same call. */
export async function decideLoyaltyPointAdjustment(client: LoyaltyPointsMutationRpcClient, input: DecideLoyaltyPointAdjustmentInput): Promise<LoyaltyPointAdjustmentRequest> {
  const v = DecideLoyaltyPointAdjustmentInputSchema.parse(input);
  return callRpc(
    client,
    "decide_loyalty_point_adjustment",
    {
      p_tenant_id: v.tenantId,
      p_adjustment_id: v.adjustmentId,
      p_expected_version: v.expectedVersion,
      p_decision: v.decision,
      p_decision_notes: v.decisionNotes,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyPointAdjustmentRequest,
  );
}
