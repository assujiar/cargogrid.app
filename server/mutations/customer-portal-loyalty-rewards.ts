/**
 * Reward Catalogue mutation primitives (CPL-320, CG-S13-CPL-022). Thin,
 * typed wrappers around every write RPC in supabase/migrations/
 * 20260801220000_create_customer_portal_loyalty_reward_catalogue.sql -- ALL
 * of them are staff-gated (LYL:Create/Edit/Configure) internally by the RPC
 * itself; there is no customer-initiated write in this capability (this is
 * a catalogue-only capability -- CPL-321's own future scope is the actual
 * redemption transaction). None of these exports should ever be called
 * from a customer-facing Server Action.
 *
 * reserveLoyaltyRewardStockUnit is wrapped for completeness/future use
 * though no UI action calls it yet -- mirrors CPL-318's own
 * consumeLoyaltyPointsFifo precedent exactly (a real, race-safe primitive
 * with no production caller in this checkpoint, ready for CPL-321).
 *
 * Mirrors server/mutations/customer-portal-loyalty-tier.ts's own known-
 * error-code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyReward,
  parseLoyaltyRewardStockReservation,
  CreateLoyaltyRewardDraftInputSchema,
  UpdateLoyaltyRewardDraftInputSchema,
  PublishLoyaltyRewardInputSchema,
  PauseLoyaltyRewardInputSchema,
  ResumeLoyaltyRewardInputSchema,
  ArchiveLoyaltyRewardInputSchema,
  ReserveLoyaltyRewardStockUnitInputSchema,
  type CreateLoyaltyRewardDraftInput,
  type UpdateLoyaltyRewardDraftInput,
  type PublishLoyaltyRewardInput,
  type PauseLoyaltyRewardInput,
  type ResumeLoyaltyRewardInput,
  type ArchiveLoyaltyRewardInput,
  type ReserveLoyaltyRewardStockUnitInput,
  type LoyaltyReward,
  type LoyaltyRewardStockReservation,
} from "../contracts/customer-portal-loyalty-rewards/customer-portal-loyalty-rewards.ts";

export type LoyaltyRewardMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_REWARD_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_reward_name",
  "invalid_reward_type",
  "invalid_min_points_required",
  "invalid_total_stock",
  "invalid_internal_cost",
  "invalid_min_tier_id",
  "invalid_file_id",
  "loyalty_program_not_found",
  "draft_already_exists",
  "loyalty_reward_not_found",
  "stale_version",
  "invalid_transition",
  "reward_publish_conflict",
  "invalid_quantity",
  "invalid_idempotency_key",
  "reward_not_available_for_reservation",
  "insufficient_reward_stock",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyRewardMutationErrorCode = (typeof LOYALTY_REWARD_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyRewardMutationErrorCode = KnownLoyaltyRewardMutationErrorCode | "mutation_failed";

export class LoyaltyRewardMutationError extends Error {
  readonly code: LoyaltyRewardMutationErrorCode;

  constructor(code: LoyaltyRewardMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyRewardMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyRewardMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_REWARD_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyRewardMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LoyaltyRewardMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyRewardMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyRewardMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

// ===========================================================================
// Reward lifecycle: draft (LYL:Create/Edit) -> published -> paused/resumed
// -> archived (LYL:Configure)
// ===========================================================================

export async function createLoyaltyRewardDraft(client: LoyaltyRewardMutationRpcClient, input: CreateLoyaltyRewardDraftInput): Promise<LoyaltyReward> {
  const v = CreateLoyaltyRewardDraftInputSchema.parse(input);
  return callRpc(
    client,
    "create_loyalty_reward_draft",
    {
      p_tenant_id: v.tenantId,
      p_program_id: v.programId,
      p_reward_name: v.rewardName,
      p_reward_type: v.rewardType,
      p_description: v.description,
      p_terms_text: v.termsText,
      p_min_tier_id: v.minTierId,
      p_min_points_required: v.minPointsRequired,
      p_total_stock: v.totalStock,
      p_internal_cost: v.internalCost,
      p_vendor_ref: v.vendorRef,
      p_file_id: v.fileId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyReward,
  );
}

export async function updateLoyaltyRewardDraft(client: LoyaltyRewardMutationRpcClient, input: UpdateLoyaltyRewardDraftInput): Promise<LoyaltyReward> {
  const v = UpdateLoyaltyRewardDraftInputSchema.parse(input);
  return callRpc(
    client,
    "update_loyalty_reward_draft",
    {
      p_tenant_id: v.tenantId,
      p_reward_id: v.rewardId,
      p_expected_version: v.expectedVersion,
      p_reward_name: v.rewardName,
      p_reward_type: v.rewardType,
      p_description: v.description,
      p_terms_text: v.termsText,
      p_min_tier_id: v.minTierId,
      p_min_points_required: v.minPointsRequired,
      p_total_stock: v.totalStock,
      p_internal_cost: v.internalCost,
      p_vendor_ref: v.vendorRef,
      p_file_id: v.fileId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyReward,
  );
}

/** Locks this reward version forever, supersedes the SAME (program, reward_name)'s own prior LIVE (published or paused) version, if any, in the same transaction. */
export async function publishLoyaltyReward(client: LoyaltyRewardMutationRpcClient, input: PublishLoyaltyRewardInput): Promise<LoyaltyReward> {
  const v = PublishLoyaltyRewardInputSchema.parse(input);
  return callRpc(
    client,
    "publish_loyalty_reward",
    {
      p_tenant_id: v.tenantId,
      p_reward_id: v.rewardId,
      p_expected_version: v.expectedVersion,
      p_effective_from: v.effectiveFrom,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyReward,
  );
}

/** Reason is optional -- pausing a reward is an ordinary merchandising/availability decision, not a governance/fraud action (unlike CPL-317's own mandatory hold reason). */
export async function pauseLoyaltyReward(client: LoyaltyRewardMutationRpcClient, input: PauseLoyaltyRewardInput): Promise<LoyaltyReward> {
  const v = PauseLoyaltyRewardInputSchema.parse(input);
  return callRpc(
    client,
    "pause_loyalty_reward",
    {
      p_tenant_id: v.tenantId,
      p_reward_id: v.rewardId,
      p_expected_version: v.expectedVersion,
      p_reason: v.reason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyReward,
  );
}

/** The structural inverse of pauseLoyaltyReward -- disclosed 6th function beyond the task's own literal 5-function list (migration design decision 6). */
export async function resumeLoyaltyReward(client: LoyaltyRewardMutationRpcClient, input: ResumeLoyaltyRewardInput): Promise<LoyaltyReward> {
  const v = ResumeLoyaltyRewardInputSchema.parse(input);
  return callRpc(
    client,
    "resume_loyalty_reward",
    {
      p_tenant_id: v.tenantId,
      p_reward_id: v.rewardId,
      p_expected_version: v.expectedVersion,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyReward,
  );
}

export async function archiveLoyaltyReward(client: LoyaltyRewardMutationRpcClient, input: ArchiveLoyaltyRewardInput): Promise<LoyaltyReward> {
  const v = ArchiveLoyaltyRewardInputSchema.parse(input);
  return callRpc(
    client,
    "archive_loyalty_reward",
    {
      p_tenant_id: v.tenantId,
      p_reward_id: v.rewardId,
      p_expected_version: v.expectedVersion,
      p_reason: v.reason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyReward,
  );
}

// ===========================================================================
// Stock (LYL:Edit) -- design decision 7, never called by any production
// path in this checkpoint.
// ===========================================================================

/** The real, race-safe stock-reservation primitive. Never composes eligibility/effective-date checks of its own -- CPL-321's own future redemption RPC is responsible for both, before calling this. */
export async function reserveLoyaltyRewardStockUnit(client: LoyaltyRewardMutationRpcClient, input: ReserveLoyaltyRewardStockUnitInput): Promise<LoyaltyRewardStockReservation> {
  const v = ReserveLoyaltyRewardStockUnitInputSchema.parse(input);
  return callRpc(
    client,
    "reserve_loyalty_reward_stock_unit",
    {
      p_tenant_id: v.tenantId,
      p_reward_id: v.rewardId,
      p_quantity: v.quantity,
      p_idempotency_key: v.idempotencyKey,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
      p_reason: v.reason,
    },
    parseLoyaltyRewardStockReservation,
  );
}
