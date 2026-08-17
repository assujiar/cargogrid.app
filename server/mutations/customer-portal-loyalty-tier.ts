/**
 * Membership Tier mutation primitives (CPL-317, CG-S13-CPL-019). Thin,
 * typed wrappers around every write RPC in supabase/migrations/
 * 20260801190000_create_customer_portal_loyalty_membership_tier.sql -- ALL
 * of them are staff-gated (LYL:Create/Edit/Configure) internally by the RPC
 * itself; there is no customer-initiated write in this capability (ADR-0024
 * Part B: recalculation/holds are staff/system-only). None of these exports
 * should ever be called from a customer-facing Server Action.
 *
 * Mirrors server/mutations/customer-portal-loyalty-program.ts's own known-
 * error-code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyTierDefinition,
  parseLoyaltyAccountTierMovement,
  parseLoyaltyAccountTierHold,
  CreateLoyaltyTierDefinitionInputSchema,
  UpdateLoyaltyTierDefinitionDraftInputSchema,
  PublishLoyaltyTierDefinitionInputSchema,
  RecalculateCustomerLoyaltyTierInputSchema,
  HoldLoyaltyAccountTierBenefitsInputSchema,
  ReleaseLoyaltyAccountTierBenefitsInputSchema,
  type CreateLoyaltyTierDefinitionInput,
  type UpdateLoyaltyTierDefinitionDraftInput,
  type PublishLoyaltyTierDefinitionInput,
  type RecalculateCustomerLoyaltyTierInput,
  type HoldLoyaltyAccountTierBenefitsInput,
  type ReleaseLoyaltyAccountTierBenefitsInput,
  type LoyaltyTierDefinition,
  type LoyaltyAccountTierMovement,
  type LoyaltyAccountTierHold,
} from "../contracts/customer-portal-loyalty-tier/customer-portal-loyalty-tier.ts";

export type LoyaltyTierMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_TIER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_tier_name",
  "invalid_tier_rank",
  "invalid_threshold_dimension",
  "invalid_threshold_value",
  "invalid_benefits",
  "invalid_review_period_days",
  "loyalty_program_not_found",
  "draft_already_exists",
  "loyalty_tier_definition_not_found",
  "stale_version",
  "invalid_transition",
  "tier_rank_conflict",
  "loyalty_account_not_found",
  "loyalty_account_closed",
  "unsupported_threshold_dimension",
  "no_eligible_tier_definition",
  "reason_required",
  "loyalty_account_tier_hold_not_found",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyTierMutationErrorCode = (typeof LOYALTY_TIER_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyTierMutationErrorCode = KnownLoyaltyTierMutationErrorCode | "mutation_failed";

export class LoyaltyTierMutationError extends Error {
  readonly code: LoyaltyTierMutationErrorCode;

  constructor(code: LoyaltyTierMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyTierMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyTierMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_TIER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyTierMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LoyaltyTierMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyTierMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyTierMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

// ===========================================================================
// Tier definition lifecycle: draft (LYL:Create/Edit) -> published (LYL:Configure)
// ===========================================================================

export async function createLoyaltyTierDefinition(client: LoyaltyTierMutationRpcClient, input: CreateLoyaltyTierDefinitionInput): Promise<LoyaltyTierDefinition> {
  const v = CreateLoyaltyTierDefinitionInputSchema.parse(input);
  return callRpc(
    client,
    "create_loyalty_tier_definition",
    {
      p_tenant_id: v.tenantId,
      p_program_id: v.programId,
      p_tier_name: v.tierName,
      p_tier_rank: v.tierRank,
      p_threshold_dimension: v.thresholdDimension,
      p_threshold_value: v.thresholdValue,
      p_benefits: v.benefits,
      p_review_period_days: v.reviewPeriodDays,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyTierDefinition,
  );
}

export async function updateLoyaltyTierDefinitionDraft(client: LoyaltyTierMutationRpcClient, input: UpdateLoyaltyTierDefinitionDraftInput): Promise<LoyaltyTierDefinition> {
  const v = UpdateLoyaltyTierDefinitionDraftInputSchema.parse(input);
  return callRpc(
    client,
    "update_loyalty_tier_definition_draft",
    {
      p_tenant_id: v.tenantId,
      p_tier_definition_id: v.tierDefinitionId,
      p_expected_version: v.expectedVersion,
      p_tier_name: v.tierName,
      p_tier_rank: v.tierRank,
      p_threshold_dimension: v.thresholdDimension,
      p_threshold_value: v.thresholdValue,
      p_benefits: v.benefits,
      p_review_period_days: v.reviewPeriodDays,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyTierDefinition,
  );
}

/** Locks this tier definition version forever, supersedes the SAME (program, tier_name)'s own prior published version, if any, in the same transaction. */
export async function publishLoyaltyTierDefinition(client: LoyaltyTierMutationRpcClient, input: PublishLoyaltyTierDefinitionInput): Promise<LoyaltyTierDefinition> {
  const v = PublishLoyaltyTierDefinitionInputSchema.parse(input);
  return callRpc(
    client,
    "publish_loyalty_tier_definition",
    {
      p_tenant_id: v.tenantId,
      p_tier_definition_id: v.tierDefinitionId,
      p_expected_version: v.expectedVersion,
      p_effective_from: v.effectiveFrom,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyTierDefinition,
  );
}

// ===========================================================================
// Recalculation (LYL:Edit)
// ===========================================================================

/**
 * Idempotent by construction (design decision 10) -- calling this
 * repeatedly with no underlying eligibility change is a safe no-op, never a
 * spurious movement row. Upgrades apply immediately; downgrades are gated
 * on the account's own current tier grace window (next_review_at).
 * On-demand/staff-triggered only in this checkpoint (no automatic job/
 * trigger wiring -- ISS-2026-127).
 */
export async function recalculateCustomerLoyaltyTier(client: LoyaltyTierMutationRpcClient, input: RecalculateCustomerLoyaltyTierInput): Promise<LoyaltyAccountTierMovement> {
  const v = RecalculateCustomerLoyaltyTierInputSchema.parse(input);
  return callRpc(
    client,
    "recalculate_customer_loyalty_tier",
    {
      p_tenant_id: v.tenantId,
      p_loyalty_account_id: v.loyaltyAccountId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyAccountTierMovement,
  );
}

// ===========================================================================
// Fraud hold (LYL:Configure)
// ===========================================================================

/** Idempotent -- holding an already-held account is a safe no-op returning the unchanged row. */
export async function holdLoyaltyAccountTierBenefits(client: LoyaltyTierMutationRpcClient, input: HoldLoyaltyAccountTierBenefitsInput): Promise<LoyaltyAccountTierHold> {
  const v = HoldLoyaltyAccountTierBenefitsInputSchema.parse(input);
  return callRpc(
    client,
    "hold_loyalty_account_tier_benefits",
    {
      p_tenant_id: v.tenantId,
      p_loyalty_account_id: v.loyaltyAccountId,
      p_reason: v.reason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyAccountTierHold,
  );
}

export async function releaseLoyaltyAccountTierBenefits(client: LoyaltyTierMutationRpcClient, input: ReleaseLoyaltyAccountTierBenefitsInput): Promise<LoyaltyAccountTierHold> {
  const v = ReleaseLoyaltyAccountTierBenefitsInputSchema.parse(input);
  return callRpc(
    client,
    "release_loyalty_account_tier_benefits",
    {
      p_tenant_id: v.tenantId,
      p_loyalty_account_id: v.loyaltyAccountId,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyAccountTierHold,
  );
}
