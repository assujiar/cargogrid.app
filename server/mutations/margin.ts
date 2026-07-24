/**
 * Margin Calculation mutation primitives (COM-150, CG-S7-COM-009). Thin, typed wrappers
 * around app.create_margin_rule_version / app.publish_margin_rule_version /
 * app.calculate_margin / app.override_margin_threshold
 * (supabase/migrations/20260724180000_create_commercial_margin_calculation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateMarginRuleVersionInputSchema,
  PublishMarginRuleVersionInputSchema,
  CalculateMarginInputSchema,
  OverrideMarginThresholdInputSchema,
  parseMarginRuleVersion,
  parseMarginCalculation,
  type CreateMarginRuleVersionInput,
  type PublishMarginRuleVersionInput,
  type CalculateMarginInput,
  type OverrideMarginThresholdInput,
  type MarginRuleVersion,
  type MarginCalculation,
} from "../contracts/margin/margin.ts";

export type MarginMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const MARGIN_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "margin_rule_not_found",
  "stale_version",
  "invalid_transition",
  "superseded_rule_not_found",
  "invalid_supersede",
  "active_rule_exists",
  "rate_selection_not_found",
  "mixed_currency",
  "no_active_margin_rule",
  "invalid_discount",
  "margin_calculation_not_found",
  "reason_required",
] as const;
type KnownMarginMutationErrorCode = (typeof MARGIN_KNOWN_MUTATION_ERROR_CODES)[number];
export type MarginMutationErrorCode = KnownMarginMutationErrorCode | "mutation_failed" | "invalid_response";

export class MarginMutationError extends Error {
  readonly code: MarginMutationErrorCode;

  constructor(code: MarginMutationErrorCode, message: string) {
    super(message);
    this.name = "MarginMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MarginMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MARGIN_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownMarginMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: MarginMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new MarginMutationError(classifyError(error.message), error.message);
  }
  return data;
}

async function callAndParseRuleVersion(client: MarginMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<MarginRuleVersion> {
  const data = await callRpc(client, fn, args);
  if (!data || typeof data !== "object") {
    throw new MarginMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseMarginRuleVersion(data as Record<string, unknown>);
}

/** Draft creation, gated by COM:Create. */
export async function createMarginRuleVersion(client: MarginMutationRpcClient, input: CreateMarginRuleVersionInput): Promise<MarginRuleVersion> {
  const parsedInput = CreateMarginRuleVersionInputSchema.parse(input);
  return callAndParseRuleVersion(client, "create_margin_rule_version", {
    p_tenant_id: parsedInput.tenantId,
    p_minimum_margin_pct: parsedInput.minimumMarginPct,
    p_rounding_mode: parsedInput.roundingMode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** draft -> published, gated by COM:Approve. Supplying supersedesVersionId archives the tenant's prior published rule first (at most one published rule per tenant). */
export async function publishMarginRuleVersion(client: MarginMutationRpcClient, input: PublishMarginRuleVersionInput): Promise<MarginRuleVersion> {
  const parsedInput = PublishMarginRuleVersionInputSchema.parse(input);
  return callAndParseRuleVersion(client, "publish_margin_rule_version", {
    p_rule_version_id: parsedInput.ruleVersionId,
    p_expected_version: parsedInput.expectedVersion,
    p_supersedes_version_id: parsedInput.supersedesVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Requires both COM:Edit and COM:View cost. Fails closed on mixed currency or no published margin rule. A repeated call for the same rateSelectionId supersedes the prior current calculation. */
export async function calculateMargin(client: MarginMutationRpcClient, input: CalculateMarginInput): Promise<MarginCalculation> {
  const parsedInput = CalculateMarginInputSchema.parse(input);
  const data = await callRpc(client, "calculate_margin", {
    p_rate_selection_id: parsedInput.rateSelectionId,
    p_sell_amount: parsedInput.sellAmount,
    p_sell_currency: parsedInput.sellCurrency,
    p_discount_pct: parsedInput.discountPct,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new MarginMutationError("invalid_response", "calculate_margin returned no row");
  }
  // app.calculate_margin returns an app.margin_calculations base-table row (no cost_masked/
  // sell_masked columns -- those are added only by app.margin_calculations_directory) --
  // the caller already passed COM:View cost to reach this point, so nothing is masked.
  const row = data as Record<string, unknown>;
  return parseMarginCalculation({ ...row, cost_masked: false, sell_masked: false });
}

/** Requires COM:Approve, a non-empty reason, and an un-overridden requires_approval result. Never changes the source cost/margin figures. */
export async function overrideMarginThreshold(client: MarginMutationRpcClient, input: OverrideMarginThresholdInput): Promise<MarginCalculation> {
  const parsedInput = OverrideMarginThresholdInputSchema.parse(input);
  const data = await callRpc(client, "override_margin_threshold", {
    p_margin_calculation_id: parsedInput.marginCalculationId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new MarginMutationError("invalid_response", "override_margin_threshold returned no row");
  }
  const row = data as Record<string, unknown>;
  return parseMarginCalculation({ ...row, cost_masked: false, sell_masked: false });
}
