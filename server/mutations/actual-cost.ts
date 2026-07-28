/**
 * Actual Cost mutation primitives (OPS-178, CG-S8-OPS-012). Thin, typed wrappers
 * around the RPCs in supabase/migrations/20260728110000_create_operations_actual_cost.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateActualCostDraftInputSchema,
  AddActualCostComponentInputSchema,
  RemoveActualCostComponentInputSchema,
  SubmitActualCostInputSchema,
  DecideActualCostInputSchema,
  CreateActualCostAdjustmentInputSchema,
  parseShipmentActualCost,
  parseShipmentActualCostComponent,
  type CreateActualCostDraftInput,
  type AddActualCostComponentInput,
  type RemoveActualCostComponentInput,
  type SubmitActualCostInput,
  type DecideActualCostInput,
  type CreateActualCostAdjustmentInput,
  type ShipmentActualCost,
  type ShipmentActualCostComponent,
} from "../contracts/actual-cost/actual-cost.ts";

export type ActualCostMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ACTUAL_COST_KNOWN_MUTATION_ERROR_CODES = [
  "shipment_order_not_found",
  "actual_cost_already_exists",
  "actual_cost_not_found",
  "actual_cost_component_not_found",
  "invalid_transition",
  "actual_cost_vendor_required",
  "actual_cost_assignment_mismatch",
  "actual_cost_document_mismatch",
  "concurrent_modification",
  "actual_cost_no_components",
  "actual_cost_invalid_decision",
  "actual_cost_rejection_reason_required",
  "actual_cost_adjustment_reason_required",
  "actual_cost_not_current",
  "insufficient_authority",
] as const;
type KnownActualCostMutationErrorCode = (typeof ACTUAL_COST_KNOWN_MUTATION_ERROR_CODES)[number];
export type ActualCostMutationErrorCode = KnownActualCostMutationErrorCode | "mutation_failed" | "invalid_response";

export class ActualCostMutationError extends Error {
  readonly code: ActualCostMutationErrorCode;

  constructor(code: ActualCostMutationErrorCode, message: string) {
    super(message);
    this.name = "ActualCostMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ActualCostMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ACTUAL_COST_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownActualCostMutationErrorCode) : "mutation_failed";
}

export async function createActualCostDraft(client: ActualCostMutationRpcClient, input: CreateActualCostDraftInput): Promise<ShipmentActualCost> {
  const parsedInput = CreateActualCostDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_actual_cost_draft", {
    p_tenant_id: parsedInput.tenantId,
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_currency: parsedInput.currency,
    p_estimated_amount: parsedInput.estimatedAmount ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ActualCostMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ActualCostMutationError("invalid_response", "create_actual_cost_draft returned no row");
  }
  return parseShipmentActualCost(data as Record<string, unknown>);
}

/** amount is always server-computed (quantity*rate/minimum + surcharge, exact numeric) -- never accepted from the caller. */
export async function addActualCostComponent(client: ActualCostMutationRpcClient, input: AddActualCostComponentInput): Promise<ShipmentActualCostComponent> {
  const parsedInput = AddActualCostComponentInputSchema.parse(input);
  const { data, error } = await client.rpc("add_actual_cost_component", {
    p_actual_cost_id: parsedInput.actualCostId,
    p_category: parsedInput.category,
    p_source_type: parsedInput.sourceType,
    p_vendor_id: parsedInput.vendorId ?? null,
    p_assignment_id: parsedInput.assignmentId ?? null,
    p_document_file_id: parsedInput.documentFileId ?? null,
    p_description: parsedInput.description ?? null,
    p_quantity: parsedInput.quantity,
    p_uom: parsedInput.uom ?? null,
    p_rate: parsedInput.rate,
    p_minimum_charge: parsedInput.minimumCharge ?? null,
    p_surcharge: parsedInput.surcharge ?? 0,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ActualCostMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ActualCostMutationError("invalid_response", "add_actual_cost_component returned no row");
  }
  return parseShipmentActualCostComponent(data as Record<string, unknown>);
}

export async function removeActualCostComponent(client: ActualCostMutationRpcClient, input: RemoveActualCostComponentInput): Promise<void> {
  const parsedInput = RemoveActualCostComponentInputSchema.parse(input);
  const { error } = await client.rpc("remove_actual_cost_component", {
    p_component_id: parsedInput.componentId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ActualCostMutationError(classifyError(error.message), error.message);
  }
}

export async function submitActualCost(client: ActualCostMutationRpcClient, input: SubmitActualCostInput): Promise<ShipmentActualCost> {
  const parsedInput = SubmitActualCostInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_actual_cost", {
    p_actual_cost_id: parsedInput.actualCostId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ActualCostMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ActualCostMutationError("invalid_response", "submit_actual_cost returned no row");
  }
  return parseShipmentActualCost(data as Record<string, unknown>);
}

/** rejected requires a non-empty reason; approved records the approver identity/timestamp. */
export async function decideActualCost(client: ActualCostMutationRpcClient, input: DecideActualCostInput): Promise<ShipmentActualCost> {
  const parsedInput = DecideActualCostInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_actual_cost", {
    p_actual_cost_id: parsedInput.actualCostId,
    p_decision: parsedInput.decision,
    p_reason: parsedInput.reason ?? null,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ActualCostMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ActualCostMutationError("invalid_response", "decide_actual_cost returned no row");
  }
  return parseShipmentActualCost(data as Record<string, unknown>);
}

/** approved-only; copies every component line onto a brand-new draft version -- the prior approved version and its own components are never mutated. */
export async function createActualCostAdjustment(client: ActualCostMutationRpcClient, input: CreateActualCostAdjustmentInput): Promise<ShipmentActualCost> {
  const parsedInput = CreateActualCostAdjustmentInputSchema.parse(input);
  const { data, error } = await client.rpc("create_actual_cost_adjustment", {
    p_previous_actual_cost_id: parsedInput.previousActualCostId,
    p_adjustment_reason: parsedInput.adjustmentReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ActualCostMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ActualCostMutationError("invalid_response", "create_actual_cost_adjustment returned no row");
  }
  return parseShipmentActualCost(data as Record<string, unknown>);
}
