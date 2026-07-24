/**
 * RFQ and Costing Request mutation primitives (COM-148, CG-S7-COM-007). Thin, typed
 * wrappers around app.request_costing / app.assign_costing_request /
 * app.submit_costing_response / app.revise_costing_request / app.cancel_costing_request
 * (supabase/migrations/20260724090000_create_commercial_costing_request.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RequestCostingInputSchema,
  AssignCostingRequestInputSchema,
  SubmitCostingResponseInputSchema,
  ReviseCostingRequestInputSchema,
  CancelCostingRequestInputSchema,
  parseCostingRequest,
  parseCostingResponse,
  type RequestCostingInput,
  type AssignCostingRequestInput,
  type SubmitCostingResponseInput,
  type ReviseCostingRequestInput,
  type CancelCostingRequestInput,
  type CostingRequest,
  type CostingResponse,
} from "../contracts/costing/costing.ts";

export type CostingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const COSTING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "opportunity_not_found",
  "costing_request_not_found",
  "requirements_incomplete",
  "stale_version",
  "invalid_transition",
  "unknown_request_component",
  "components_required",
  "no_new_version",
  "reason_required",
] as const;
type KnownCostingMutationErrorCode = (typeof COSTING_KNOWN_MUTATION_ERROR_CODES)[number];
export type CostingMutationErrorCode = KnownCostingMutationErrorCode | "mutation_failed" | "invalid_response";

export class CostingMutationError extends Error {
  readonly code: CostingMutationErrorCode;

  constructor(code: CostingMutationErrorCode, message: string) {
    super(message);
    this.name = "CostingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CostingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (COSTING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCostingMutationErrorCode)
    : "mutation_failed";
}

async function callRpc(client: CostingMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CostingMutationError(classifyError(error.message), error.message);
  }
  return data;
}

async function callAndParseRequest(client: CostingMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CostingRequest> {
  const data = await callRpc(client, fn, args);
  if (!data || typeof data !== "object") {
    throw new CostingMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseCostingRequest(data as Record<string, unknown>);
}

function toRequestComponentsJson(components: RequestCostingInput["components"]): Record<string, unknown>[] {
  return (components ?? []).map((component) => ({
    code: component.code,
    description: component.description ?? null,
    quantity: component.quantity ?? null,
    unit: component.unit ?? null,
  }));
}

/** Idempotent on (tenant, opportunityId, source_opportunity_version). Requires app.get_opportunity_costing_readiness to report ready=true first. */
export async function requestCosting(client: CostingMutationRpcClient, input: RequestCostingInput): Promise<CostingRequest> {
  const parsedInput = RequestCostingInputSchema.parse(input);
  return callAndParseRequest(client, "request_costing", {
    p_opportunity_id: parsedInput.opportunityId,
    p_components: toRequestComponentsJson(parsedInput.components),
    p_due_at: parsedInput.dueAt,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** pending -> assigned (or reassign while assigned). */
export async function assignCostingRequest(client: CostingMutationRpcClient, input: AssignCostingRequestInput): Promise<CostingRequest> {
  const parsedInput = AssignCostingRequestInputSchema.parse(input);
  return callAndParseRequest(client, "assign_costing_request", {
    p_request_id: parsedInput.requestId,
    p_expected_version: parsedInput.expectedVersion,
    p_assignee_user_id: parsedInput.assigneeUserId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** Requires both COM:Edit and COM:View cost. total_amount is always computed server-side as the sum of the supplied components. */
export async function submitCostingResponse(client: CostingMutationRpcClient, input: SubmitCostingResponseInput): Promise<CostingResponse> {
  const parsedInput = SubmitCostingResponseInputSchema.parse(input);
  const data = await callRpc(client, "submit_costing_response", {
    p_request_id: parsedInput.requestId,
    p_source_type: parsedInput.sourceType,
    p_vendor_ref: parsedInput.vendorRef,
    p_currency: parsedInput.currency,
    p_effective_at: parsedInput.effectiveAt,
    p_expiry_at: parsedInput.expiryAt,
    p_components: parsedInput.components.map((component) => ({
      requestComponentId: component.requestComponentId,
      amount: component.amount,
    })),
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (!data || typeof data !== "object") {
    throw new CostingMutationError("invalid_response", "submit_costing_response returned no row");
  }
  return parseCostingResponse(data as Record<string, unknown>);
}

/** Creates a new costing request pinned to the opportunity's current version/requirements and marks the source superseded. Raises no_new_version if the opportunity has not changed. */
export async function reviseCostingRequest(client: CostingMutationRpcClient, input: ReviseCostingRequestInput): Promise<CostingRequest> {
  const parsedInput = ReviseCostingRequestInputSchema.parse(input);
  return callAndParseRequest(client, "revise_costing_request", {
    p_request_id: parsedInput.requestId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_created_by: parsedInput.createdBy,
  });
}

/** Requires a non-empty reason. Cannot cancel an already-cancelled or superseded request. */
export async function cancelCostingRequest(client: CostingMutationRpcClient, input: CancelCostingRequestInput): Promise<CostingRequest> {
  const parsedInput = CancelCostingRequestInputSchema.parse(input);
  return callAndParseRequest(client, "cancel_costing_request", {
    p_request_id: parsedInput.requestId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
