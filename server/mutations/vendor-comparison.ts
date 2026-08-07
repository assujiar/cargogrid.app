/**
 * Vendor Comparison mutation primitives (PRC-258, CG-S11-PRC-009). Thin,
 * typed wrappers around the write RPCs supabase/migrations/
 * 20260730650000_create_procurement_vendor_comparison.sql adds -- the same
 * KNOWN_MUTATION_ERROR_CODES / classifyError / callRpc shape
 * server/mutations/rfq.ts already establishes for this checkpoint's own
 * template.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorComparisonInputSchema,
  ReviseVendorComparisonInputSchema,
  LinkVendorComparisonOfferRateInputSchema,
  SetVendorComparisonOfferInclusionInputSchema,
  ScoreVendorComparisonOfferCriterionInputSchema,
  RecommendVendorComparisonOfferInputSchema,
  SubmitVendorComparisonForApprovalInputSchema,
  CancelVendorComparisonInputSchema,
  parseVendorComparison,
  parseVendorComparisonOffer,
  parseVendorComparisonOfferScore,
  type CreateVendorComparisonInput,
  type ReviseVendorComparisonInput,
  type LinkVendorComparisonOfferRateInput,
  type SetVendorComparisonOfferInclusionInput,
  type ScoreVendorComparisonOfferCriterionInput,
  type RecommendVendorComparisonOfferInput,
  type SubmitVendorComparisonForApprovalInput,
  type CancelVendorComparisonInput,
  type VendorComparison,
  type VendorComparisonOffer,
  type VendorComparisonOfferScore,
} from "../contracts/vendor-comparison/vendor-comparison.ts";

export type VendorComparisonMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_COMPARISON_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "vendor_comparison_not_found",
  "vendor_comparison_offer_not_found",
  "rfq_not_found",
  "rate_version_not_found",
  "tenant_mismatch",
  "vendor_mismatch",
  "invalid_source_status",
  "invalid_rate_status",
  "invalid_basis_quantity",
  "invalid_currency",
  "invalid_criteria",
  "invalid_criterion",
  "invalid_score",
  "unknown_criterion",
  "criterion_key_required",
  "excluded_offer",
  "no_comparable_responses",
  "fx_conversion_failed",
  "idempotency_key_required",
  "idempotency_key_conflict",
  "reason_required",
  "stale_version",
  "invalid_transition",
  "invalid_status_filter",
] as const;
type KnownVendorComparisonMutationErrorCode = (typeof VENDOR_COMPARISON_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorComparisonMutationErrorCode = KnownVendorComparisonMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorComparisonMutationError extends Error {
  readonly code: VendorComparisonMutationErrorCode;

  constructor(code: VendorComparisonMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorComparisonMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorComparisonMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_COMPARISON_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorComparisonMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: VendorComparisonMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorComparisonMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireComparisonRow(data: unknown, fn: string): VendorComparison {
  if (!data || typeof data !== "object") {
    throw new VendorComparisonMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseVendorComparison(data as Record<string, unknown>);
}

function requireOfferRow(data: unknown, fn: string): VendorComparisonOffer {
  if (!data || typeof data !== "object") {
    throw new VendorComparisonMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseVendorComparisonOffer(data as Record<string, unknown>);
}

function requireOfferScoreRow(data: unknown, fn: string): VendorComparisonOfferScore {
  if (!data || typeof data !== "object") {
    throw new VendorComparisonMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseVendorComparisonOfferScore(data as Record<string, unknown>);
}

/** Creates (or, on idempotency-key replay, returns the existing) a comparison from a closed RFQ's own submitted, comparison-eligible responses. status=draft. */
export async function createVendorComparison(client: VendorComparisonMutationRpcClient, input: CreateVendorComparisonInput): Promise<VendorComparison> {
  const parsed = CreateVendorComparisonInputSchema.parse(input);
  const data = await callRpc(client, "create_vendor_comparison", {
    p_tenant_id: parsed.tenantId,
    p_rfq_id: parsed.rfqId,
    p_comparison_currency: parsed.comparisonCurrency,
    p_basis_weight: parsed.basisWeight,
    p_basis_volume: parsed.basisVolume,
    p_basis_quantity: parsed.basisQuantity,
    p_criteria: parsed.criteria,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireComparisonRow(data, "create_vendor_comparison");
}

/** Only from status draft|recommended, mandatory reason. Marks the current version superseded and creates a new draft version, re-normalizing all offers fresh. Idempotent on (tenant_id, idempotencyKey). */
export async function reviseVendorComparison(client: VendorComparisonMutationRpcClient, input: ReviseVendorComparisonInput): Promise<VendorComparison> {
  const parsed = ReviseVendorComparisonInputSchema.parse(input);
  const data = await callRpc(client, "revise_vendor_comparison", {
    p_comparison_id: parsed.comparisonId,
    p_comparison_currency: parsed.comparisonCurrency,
    p_basis_weight: parsed.basisWeight,
    p_basis_volume: parsed.basisVolume,
    p_basis_quantity: parsed.basisQuantity,
    p_criteria: parsed.criteria,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireComparisonRow(data, "revise_vendor_comparison");
}

/** Attaches an approved, same-vendor rate version to one offer -- composes app.calculate_vendor_rate then app.convert_finance_amount to replace the offer's normalization source. Only while the comparison is draft|recommended. */
export async function linkVendorComparisonOfferRate(client: VendorComparisonMutationRpcClient, input: LinkVendorComparisonOfferRateInput): Promise<VendorComparisonOffer> {
  const parsed = LinkVendorComparisonOfferRateInputSchema.parse(input);
  const data = await callRpc(client, "link_vendor_comparison_offer_rate", {
    p_comparison_offer_id: parsed.comparisonOfferId,
    p_rate_version_id: parsed.rateVersionId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireOfferRow(data, "link_vendor_comparison_offer_rate");
}

/** Reviewer-driven include/exclude of one offer -- mandatory reason to exclude. Never touches the underlying RFQ response. Only while the comparison is draft|recommended. */
export async function setVendorComparisonOfferInclusion(client: VendorComparisonMutationRpcClient, input: SetVendorComparisonOfferInclusionInput): Promise<VendorComparisonOffer> {
  const parsed = SetVendorComparisonOfferInclusionInputSchema.parse(input);
  const data = await callRpc(client, "set_vendor_comparison_offer_inclusion", {
    p_comparison_offer_id: parsed.comparisonOfferId,
    p_included: parsed.included,
    p_reason: parsed.reason,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireOfferRow(data, "set_vendor_comparison_offer_inclusion");
}

/** Upserts one non-price criterion score (0-100) for one offer. No expectedVersion (a collaborative annotation, not a version-gated transition). Only while the comparison is draft|recommended. */
export async function scoreVendorComparisonOfferCriterion(client: VendorComparisonMutationRpcClient, input: ScoreVendorComparisonOfferCriterionInput): Promise<VendorComparisonOfferScore> {
  const parsed = ScoreVendorComparisonOfferCriterionInputSchema.parse(input);
  const data = await callRpc(client, "score_vendor_comparison_offer_criterion", {
    p_comparison_offer_id: parsed.comparisonOfferId,
    p_criterion_key: parsed.criterionKey,
    p_score: parsed.score,
    p_notes: parsed.notes,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireOfferScoreRow(data, "score_vendor_comparison_offer_criterion");
}

/** draft|recommended -> recommended. Mandatory reason whenever the recommended offer is not the lowest normalized cost among included offers. */
export async function recommendVendorComparisonOffer(client: VendorComparisonMutationRpcClient, input: RecommendVendorComparisonOfferInput): Promise<VendorComparison> {
  const parsed = RecommendVendorComparisonOfferInputSchema.parse(input);
  const data = await callRpc(client, "recommend_vendor_comparison_offer", {
    p_comparison_id: parsed.comparisonId,
    p_comparison_offer_id: parsed.comparisonOfferId,
    p_reason: parsed.reason,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireComparisonRow(data, "recommend_vendor_comparison_offer");
}

/** recommended -> submitted (terminal), gated on PRC:Approve -- the human selection/override-with-reason handoff ready for the approval engine (Prompt 259, not called from here). Mandatory reason when the selected offer differs from the recommended one. */
export async function submitVendorComparisonForApproval(client: VendorComparisonMutationRpcClient, input: SubmitVendorComparisonForApprovalInput): Promise<VendorComparison> {
  const parsed = SubmitVendorComparisonForApprovalInputSchema.parse(input);
  const data = await callRpc(client, "submit_vendor_comparison_for_approval", {
    p_comparison_id: parsed.comparisonId,
    p_selected_offer_id: parsed.selectedOfferId,
    p_selection_reason: parsed.selectionReason,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireComparisonRow(data, "submit_vendor_comparison_for_approval");
}

/** draft|recommended -> cancelled. Mandatory reason. */
export async function cancelVendorComparison(client: VendorComparisonMutationRpcClient, input: CancelVendorComparisonInput): Promise<VendorComparison> {
  const parsed = CancelVendorComparisonInputSchema.parse(input);
  const data = await callRpc(client, "cancel_vendor_comparison", {
    p_comparison_id: parsed.comparisonId,
    p_reason: parsed.reason,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireComparisonRow(data, "cancel_vendor_comparison");
}
