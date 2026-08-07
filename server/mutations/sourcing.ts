/**
 * Sourcing mutation primitives (PRC-256, CG-S11-PRC-007). Thin, typed wrappers
 * around the write RPCs
 * supabase/migrations/20260730630000_create_procurement_sourcing.sql adds --
 * the same SOURCING_KNOWN_MUTATION_ERROR_CODES / classifyError / callRpc shape
 * server/mutations/procurement-rate.ts already establishes for this
 * checkpoint's own template.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateSourcingRequestFromCostingInputSchema,
  CreateSourcingRequestFromOperationalDemandInputSchema,
  CreateProactiveSourcingRequestInputSchema,
  SubmitSourcingRequestInputSchema,
  OverrideSourcingRequestConstraintsInputSchema,
  EvaluateSourcingCandidateEligibilityInputSchema,
  ShortlistSourcingCandidateInputSchema,
  SubmitSourcingShortlistInputSchema,
  CloseSourcingRequestNoSourceInputSchema,
  CancelSourcingRequestInputSchema,
  ReopenSourcingRequestInputSchema,
  parseSourcingRequest,
  parseSourcingCandidate,
  type CreateSourcingRequestFromCostingInput,
  type CreateSourcingRequestFromOperationalDemandInput,
  type CreateProactiveSourcingRequestInput,
  type SubmitSourcingRequestInput,
  type OverrideSourcingRequestConstraintsInput,
  type EvaluateSourcingCandidateEligibilityInput,
  type ShortlistSourcingCandidateInput,
  type SubmitSourcingShortlistInput,
  type CloseSourcingRequestNoSourceInput,
  type CancelSourcingRequestInput,
  type ReopenSourcingRequestInput,
  type SourcingRequest,
  type SourcingCandidate,
} from "../contracts/sourcing/sourcing.ts";

export type SourcingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SOURCING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "sourcing_request_not_found",
  "sourcing_candidate_not_found",
  "costing_request_not_found",
  "shipment_order_not_found",
  "tenant_mismatch",
  "invalid_source_status",
  "source_demand_incomplete",
  "idempotency_key_required",
  "idempotency_key_conflict",
  "invalid_service_type",
  "invalid_origin_lane",
  "invalid_destination_lane",
  "invalid_budget_amount",
  "stale_version",
  "invalid_transition",
  "constraint_narrowing_not_allowed",
  "no_candidates_shortlisted",
  "reason_required",
  "invalid_status_filter",
  "vendor_master_record_not_found",
  "invalid_vendor_identity",
] as const;
type KnownSourcingMutationErrorCode = (typeof SOURCING_KNOWN_MUTATION_ERROR_CODES)[number];
export type SourcingMutationErrorCode = KnownSourcingMutationErrorCode | "mutation_failed" | "invalid_response";

export class SourcingMutationError extends Error {
  readonly code: SourcingMutationErrorCode;

  constructor(code: SourcingMutationErrorCode, message: string) {
    super(message);
    this.name = "SourcingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): SourcingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SOURCING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownSourcingMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: SourcingMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new SourcingMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireSourcingRequestRow(data: unknown, fn: string): SourcingRequest {
  if (!data || typeof data !== "object") {
    throw new SourcingMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseSourcingRequest(data as Record<string, unknown>);
}

function requireSourcingCandidateRow(data: unknown, fn: string): SourcingCandidate {
  if (!data || typeof data !== "object") {
    throw new SourcingMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseSourcingCandidate(data as Record<string, unknown>);
}

/** Creates (or, on idempotency-key replay, returns the existing) sourcing request sourced from a Commercial costing request. status=open directly. */
export async function createSourcingRequestFromCosting(client: SourcingMutationRpcClient, input: CreateSourcingRequestFromCostingInput): Promise<SourcingRequest> {
  const parsed = CreateSourcingRequestFromCostingInputSchema.parse(input);
  const data = await callRpc(client, "create_sourcing_request_from_costing", {
    p_tenant_id: parsed.tenantId,
    p_costing_request_id: parsed.costingRequestId,
    p_owner_user_id: parsed.ownerUserId,
    p_sla_due_at: parsed.slaDueAt,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireSourcingRequestRow(data, "create_sourcing_request_from_costing");
}

/** Creates (or, on idempotency-key replay, returns the existing) sourcing request sourced from an Operations shipment order. status=open directly. */
export async function createSourcingRequestFromOperationalDemand(
  client: SourcingMutationRpcClient,
  input: CreateSourcingRequestFromOperationalDemandInput,
): Promise<SourcingRequest> {
  const parsed = CreateSourcingRequestFromOperationalDemandInputSchema.parse(input);
  const data = await callRpc(client, "create_sourcing_request_from_operational_demand", {
    p_tenant_id: parsed.tenantId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_owner_user_id: parsed.ownerUserId,
    p_sla_due_at: parsed.slaDueAt,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireSourcingRequestRow(data, "create_sourcing_request_from_operational_demand");
}

/** Creates (or, on idempotency-key replay, returns the existing) a source-less sourcing request. status=draft -- needs submitSourcingRequest to reach open. */
export async function createProactiveSourcingRequest(client: SourcingMutationRpcClient, input: CreateProactiveSourcingRequestInput): Promise<SourcingRequest> {
  const parsed = CreateProactiveSourcingRequestInputSchema.parse(input);
  const data = await callRpc(client, "create_proactive_sourcing_request", {
    p_tenant_id: parsed.tenantId,
    p_service_type: parsed.serviceType,
    p_mode: parsed.mode,
    p_origin_lane: parsed.originLane,
    p_destination_lane: parsed.destinationLane,
    p_cargo_weight_min: parsed.cargoWeightMin,
    p_cargo_weight_max: parsed.cargoWeightMax,
    p_cargo_volume_min: parsed.cargoVolumeMin,
    p_cargo_volume_max: parsed.cargoVolumeMax,
    p_requested_pickup_at: parsed.requestedPickupAt,
    p_requested_delivery_at: parsed.requestedDeliveryAt,
    p_currency: parsed.currency,
    p_budget_amount: parsed.budgetAmount,
    p_owner_user_id: parsed.ownerUserId,
    p_sla_due_at: parsed.slaDueAt,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireSourcingRequestRow(data, "create_proactive_sourcing_request");
}

/** draft -> open. Only valid for a proactive sourcing request. Requires PRC:Edit. */
export async function submitSourcingRequest(client: SourcingMutationRpcClient, input: SubmitSourcingRequestInput): Promise<SourcingRequest> {
  const parsed = SubmitSourcingRequestInputSchema.parse(input);
  const data = await callRpc(client, "submit_sourcing_request", {
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_expected_version: parsed.expectedVersion,
  });
  return requireSourcingRequestRow(data, "submit_sourcing_request");
}

/** Governed, widen-only override of cargo_weight_max/cargo_volume_max/destination_lane. Requires PRC:Override and a mandatory reason. Only while open. */
export async function overrideSourcingRequestConstraints(client: SourcingMutationRpcClient, input: OverrideSourcingRequestConstraintsInput): Promise<SourcingRequest> {
  const parsed = OverrideSourcingRequestConstraintsInputSchema.parse(input);
  const data = await callRpc(client, "override_sourcing_request_constraints", {
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_cargo_weight_max: parsed.cargoWeightMax,
    p_cargo_volume_max: parsed.cargoVolumeMax,
    p_destination_lane: parsed.destinationLane,
    p_reason: parsed.reason,
    p_override_expires_at: parsed.overrideExpiresAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_expected_version: parsed.expectedVersion,
  });
  return requireSourcingRequestRow(data, "override_sourcing_request_constraints");
}

/** Recomputes candidate eligibility for every active vendor in the tenant (bounded to 500 per call). Requires PRC:Edit (and, composed, PRC:View for the compliance-eligibility read). Only while open. Preserves any prior shortlist decision. */
export async function evaluateSourcingCandidateEligibility(client: SourcingMutationRpcClient, input: EvaluateSourcingCandidateEligibilityInput): Promise<SourcingCandidate[]> {
  const parsed = EvaluateSourcingCandidateEligibilityInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_sourcing_candidate_eligibility", {
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) {
    throw new SourcingMutationError(classifyError(error.message), error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSourcingCandidate(row));
}

/** Shortlists (or un-shortlists) one candidate. Shortlisting an eligible candidate needs PRC:Edit; shortlisting an excluded one needs PRC:Override and a mandatory reason. Only while the parent sourcing request is open. */
export async function shortlistSourcingCandidate(client: SourcingMutationRpcClient, input: ShortlistSourcingCandidateInput): Promise<SourcingCandidate> {
  const parsed = ShortlistSourcingCandidateInputSchema.parse(input);
  const data = await callRpc(client, "shortlist_sourcing_candidate", {
    p_candidate_id: parsed.candidateId,
    p_shortlisted: parsed.shortlisted,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_expected_version: parsed.expectedVersion,
  });
  return requireSourcingCandidateRow(data, "shortlist_sourcing_candidate");
}

/** open -> shortlisted. Requires at least one shortlisted candidate, else no_candidates_shortlisted. Locks shortlist_locked_at. Requires PRC:Edit. */
export async function submitSourcingShortlist(client: SourcingMutationRpcClient, input: SubmitSourcingShortlistInput): Promise<SourcingRequest> {
  const parsed = SubmitSourcingShortlistInputSchema.parse(input);
  const data = await callRpc(client, "submit_sourcing_shortlist", {
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_expected_version: parsed.expectedVersion,
  });
  return requireSourcingRequestRow(data, "submit_sourcing_shortlist");
}

/** open -> closed_no_source. Mandatory reason. Requires PRC:Edit. */
export async function closeSourcingRequestNoSource(client: SourcingMutationRpcClient, input: CloseSourcingRequestNoSourceInput): Promise<SourcingRequest> {
  const parsed = CloseSourcingRequestNoSourceInputSchema.parse(input);
  const data = await callRpc(client, "close_sourcing_request_no_source", {
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_expected_version: parsed.expectedVersion,
  });
  return requireSourcingRequestRow(data, "close_sourcing_request_no_source");
}

/** draft or open -> cancelled. Mandatory reason. Requires PRC:Edit. */
export async function cancelSourcingRequest(client: SourcingMutationRpcClient, input: CancelSourcingRequestInput): Promise<SourcingRequest> {
  const parsed = CancelSourcingRequestInputSchema.parse(input);
  const data = await callRpc(client, "cancel_sourcing_request", {
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_expected_version: parsed.expectedVersion,
  });
  return requireSourcingRequestRow(data, "cancel_sourcing_request");
}

/** shortlisted/closed_no_source/cancelled -> open. Governed reopen, mandatory reason. Requires PRC:Override. Preserves every candidate's own shortlisted flag. */
export async function reopenSourcingRequest(client: SourcingMutationRpcClient, input: ReopenSourcingRequestInput): Promise<SourcingRequest> {
  const parsed = ReopenSourcingRequestInputSchema.parse(input);
  const data = await callRpc(client, "reopen_sourcing_request", {
    p_sourcing_request_id: parsed.sourcingRequestId,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_expected_version: parsed.expectedVersion,
  });
  return requireSourcingRequestRow(data, "reopen_sourcing_request");
}
