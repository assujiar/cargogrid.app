/**
 * Shipment Lifecycle mutation primitive (OPS-170, CG-S8-OPS-004). Thin, typed wrapper
 * around app.transition_shipment_order
 * (supabase/migrations/20260727110000_create_operations_shipment_lifecycle.sql) --
 * the one atomic, idempotent, validated entry point for every Shipment Order state
 * change. Returns the same app.shipment_orders shape server/contracts/shipment-order
 * already models, so this wrapper reuses that parser directly rather than duplicating it.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { TransitionShipmentOrderInputSchema, type TransitionShipmentOrderInput } from "../contracts/shipment-lifecycle/shipment-lifecycle.ts";
import { parseShipmentOrder, type ShipmentOrder } from "../contracts/shipment-order/shipment-order.ts";

export type ShipmentLifecycleMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SHIPMENT_LIFECYCLE_KNOWN_MUTATION_ERROR_CODES = [
  "idempotency_key_required",
  "shipment_order_not_found",
  "stale_version",
  "invalid_transition",
  "reason_required",
  "evidence_required",
  "insufficient_authority",
] as const;
type KnownShipmentLifecycleMutationErrorCode = (typeof SHIPMENT_LIFECYCLE_KNOWN_MUTATION_ERROR_CODES)[number];
export type ShipmentLifecycleMutationErrorCode = KnownShipmentLifecycleMutationErrorCode | "mutation_failed" | "invalid_response";

export class ShipmentLifecycleMutationError extends Error {
  readonly code: ShipmentLifecycleMutationErrorCode;

  constructor(code: ShipmentLifecycleMutationErrorCode, message: string) {
    super(message);
    this.name = "ShipmentLifecycleMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ShipmentLifecycleMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SHIPMENT_LIFECYCLE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownShipmentLifecycleMutationErrorCode)
    : "mutation_failed";
}

/**
 * The one atomic, idempotent, validated transition -- a retry with the same
 * idempotencyKey returns the current row unchanged, never reprocessed. Reason is
 * mandatory entering held/cancelled; evidenceRef is mandatory entering delivered/
 * epod/closed; reopening a closed shipment (-> delivered/epod) requires Supreme Admin.
 */
export async function transitionShipmentOrder(client: ShipmentLifecycleMutationRpcClient, input: TransitionShipmentOrderInput): Promise<ShipmentOrder> {
  const parsedInput = TransitionShipmentOrderInputSchema.parse(input);
  const { data, error } = await client.rpc("transition_shipment_order", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_to_status: parsedInput.toStatus,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_evidence_ref: parsedInput.evidenceRef,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ShipmentLifecycleMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ShipmentLifecycleMutationError("invalid_response", "transition_shipment_order returned no row");
  }
  return parseShipmentOrder(data as Record<string, unknown>);
}
