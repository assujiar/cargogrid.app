/**
 * Rate and Cost Lookup mutation primitives (COM-149, CG-S7-COM-008). Thin, typed
 * wrappers around app.create_rate_version / app.approve_rate_version /
 * app.reject_rate_version / app.withdraw_rate_version / app.search_vendor_rates /
 * app.select_vendor_rate (supabase/migrations/20260724150000_create_commercial_rate_cost_lookup.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateRateVersionInputSchema,
  ApproveRateVersionInputSchema,
  RejectRateVersionInputSchema,
  WithdrawRateVersionInputSchema,
  SearchVendorRatesInputSchema,
  SelectVendorRateInputSchema,
  parseRateVersion,
  parseRateVersionRecord,
  parseRateSelection,
  type CreateRateVersionInput,
  type ApproveRateVersionInput,
  type RejectRateVersionInput,
  type WithdrawRateVersionInput,
  type SearchVendorRatesInput,
  type SelectVendorRateInput,
  type RateVersion,
  type RateVersionRecord,
  type RateSelection,
} from "../contracts/rate/rate.ts";

export type RateMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const RATE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "rate_version_not_found",
  "tenant_mismatch",
  "invalid_transition",
  "stale_version",
  "reason_required",
  "invalid_adhoc_rate",
  "costing_request_not_found",
] as const;
type KnownRateMutationErrorCode = (typeof RATE_KNOWN_MUTATION_ERROR_CODES)[number];
export type RateMutationErrorCode = KnownRateMutationErrorCode | "mutation_failed" | "invalid_response";

export class RateMutationError extends Error {
  readonly code: RateMutationErrorCode;

  constructor(code: RateMutationErrorCode, message: string) {
    super(message);
    this.name = "RateMutationError";
    this.code = code;
  }
}

function classifyError(message: string): RateMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (RATE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownRateMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: RateMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new RateMutationError(classifyError(error.message), error.message);
  }
  return data;
}

async function callAndParseRateVersionRecord(client: RateMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<RateVersionRecord> {
  const data = await callRpc(client, fn, args);
  if (!data || typeof data !== "object") {
    throw new RateMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseRateVersionRecord(data as Record<string, unknown>);
}

/** Idempotent get-or-create of the vendor/lane identity row (PLT-120). Gated by app.is_support_grant_authority, not ordinary COM RBAC (ADR-0015). */
export async function createRateVersion(client: RateMutationRpcClient, input: CreateRateVersionInput): Promise<RateVersionRecord> {
  const parsedInput = CreateRateVersionInputSchema.parse(input);
  return callAndParseRateVersionRecord(client, "create_rate_version", {
    p_tenant_id: parsedInput.tenantId,
    p_vendor_code: parsedInput.vendorCode,
    p_vendor_name: parsedInput.vendorName,
    p_service_type: parsedInput.serviceType,
    p_mode: parsedInput.mode,
    p_origin_lane: parsedInput.originLane,
    p_destination_lane: parsedInput.destinationLane,
    p_equipment_type: parsedInput.equipmentType,
    p_cargo_weight_min: parsedInput.cargoWeightMin,
    p_cargo_weight_max: parsedInput.cargoWeightMax,
    p_cargo_volume_min: parsedInput.cargoVolumeMin,
    p_cargo_volume_max: parsedInput.cargoVolumeMax,
    p_currency: parsedInput.currency,
    p_base_amount: parsedInput.baseAmount,
    p_minimum_amount: parsedInput.minimumAmount,
    p_surcharge_components: parsedInput.surchargeComponents,
    p_effective_from: parsedInput.effectiveFrom,
    p_effective_to: parsedInput.effectiveTo,
    p_supersedes_version_id: parsedInput.supersedesVersionId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** pending_approval -> approved. Gated by app.is_support_grant_authority. */
export async function approveRateVersion(client: RateMutationRpcClient, input: ApproveRateVersionInput): Promise<RateVersionRecord> {
  const parsedInput = ApproveRateVersionInputSchema.parse(input);
  return callAndParseRateVersionRecord(client, "approve_rate_version", {
    p_rate_version_id: parsedInput.rateVersionId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** pending_approval -> rejected. Requires a non-empty reason. Gated by app.is_support_grant_authority. */
export async function rejectRateVersion(client: RateMutationRpcClient, input: RejectRateVersionInput): Promise<RateVersionRecord> {
  const parsedInput = RejectRateVersionInputSchema.parse(input);
  return callAndParseRateVersionRecord(client, "reject_rate_version", {
    p_rate_version_id: parsedInput.rateVersionId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** approved -> withdrawn. Requires a non-empty reason. Gated by app.is_support_grant_authority. */
export async function withdrawRateVersion(client: RateMutationRpcClient, input: WithdrawRateVersionInput): Promise<RateVersionRecord> {
  const parsedInput = WithdrawRateVersionInputSchema.parse(input);
  return callAndParseRateVersionRecord(client, "withdraw_rate_version", {
    p_rate_version_id: parsedInput.rateVersionId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** A bounded (<=200), cost-ordered shortlist lookup for one lane/service. Requires COM:View. */
export async function searchVendorRates(client: RateMutationRpcClient, input: SearchVendorRatesInput): Promise<RateVersion[]> {
  const parsedInput = SearchVendorRatesInputSchema.parse(input);
  const data = await callRpc(client, "search_vendor_rates", {
    p_tenant_id: parsedInput.tenantId,
    p_service_type: parsedInput.serviceType,
    p_origin_lane: parsedInput.originLane,
    p_destination_lane: parsedInput.destinationLane,
    p_mode: parsedInput.mode,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_limit: parsedInput.limit,
  });
  if (!Array.isArray(data)) {
    throw new RateMutationError("invalid_response", "search_vendor_rates did not return an array");
  }
  return data.map((row) => parseRateVersion(row as Record<string, unknown>));
}

/** Snapshots the selected rate (or an ad-hoc entry) into app.rate_selections for one costing request. Requires both COM:Edit and COM:View cost. */
export async function selectVendorRate(client: RateMutationRpcClient, input: SelectVendorRateInput): Promise<RateSelection> {
  const parsedInput = SelectVendorRateInputSchema.parse(input);
  const data = await callRpc(client, "select_vendor_rate", {
    p_costing_request_id: parsedInput.costingRequestId,
    p_rate_version_id: parsedInput.rateVersionId,
    p_is_adhoc: parsedInput.isAdhoc,
    p_adhoc_currency: parsedInput.adhocCurrency,
    p_adhoc_amount: parsedInput.adhocAmount,
    p_override_reason: parsedInput.overrideReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new RateMutationError("invalid_response", "select_vendor_rate returned no row");
  }
  return parseRateSelection(data as Record<string, unknown>);
}
