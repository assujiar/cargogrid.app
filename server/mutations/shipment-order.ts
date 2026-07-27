/**
 * Shipment Order mutation primitives (OPS-169, CG-S8-OPS-003). Thin, typed wrappers
 * around app.create_shipment_order_from_job / app.confirm_shipment_order /
 * app.cancel_shipment_order
 * (supabase/migrations/20260727100000_create_operations_shipment_order.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateShipmentOrderFromJobInputSchema,
  ConfirmShipmentOrderInputSchema,
  CancelShipmentOrderInputSchema,
  parseShipmentOrder,
  type CreateShipmentOrderFromJobInput,
  type ConfirmShipmentOrderInput,
  type CancelShipmentOrderInput,
  type ShipmentOrder,
} from "../contracts/shipment-order/shipment-order.ts";

export type ShipmentOrderMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const SHIPMENT_ORDER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_mode",
  "idempotency_key_required",
  "job_order_not_found",
  "job_order_not_confirmed",
  "split_reason_required",
  "over_allocation",
  "shipment_order_not_found",
  "stale_version",
  "invalid_transition",
  "cancel_reason_required",
] as const;
type KnownShipmentOrderMutationErrorCode = (typeof SHIPMENT_ORDER_KNOWN_MUTATION_ERROR_CODES)[number];
export type ShipmentOrderMutationErrorCode = KnownShipmentOrderMutationErrorCode | "mutation_failed" | "invalid_response";

export class ShipmentOrderMutationError extends Error {
  readonly code: ShipmentOrderMutationErrorCode;

  constructor(code: ShipmentOrderMutationErrorCode, message: string) {
    super(message);
    this.name = "ShipmentOrderMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ShipmentOrderMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (SHIPMENT_ORDER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownShipmentOrderMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseShipmentOrder(client: ShipmentOrderMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<ShipmentOrder> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new ShipmentOrderMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ShipmentOrderMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseShipmentOrder(data as Record<string, unknown>);
}

/**
 * The one atomic, idempotent creation action -- a retry with the same idempotencyKey,
 * including under a concurrent-insert race, returns the exact same row, never a
 * duplicate. OPS:Create-gated, requires the Job Order be confirmed. A second (or
 * later) non-cancelled Shipment Order against the same Job Order requires a
 * non-empty splitReason and is allocation-balance-checked.
 */
export async function createShipmentOrderFromJob(client: ShipmentOrderMutationRpcClient, input: CreateShipmentOrderFromJobInput): Promise<ShipmentOrder> {
  const parsedInput = CreateShipmentOrderFromJobInputSchema.parse(input);
  return callAndParseShipmentOrder(client, "create_shipment_order_from_job", {
    p_job_order_id: parsedInput.jobOrderId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_consignee: parsedInput.consignee,
    p_notify_party: parsedInput.notifyParty,
    p_service_type: parsedInput.serviceType,
    p_mode: parsedInput.mode,
    p_origin: parsedInput.origin,
    p_destination: parsedInput.destination,
    p_planned_pickup_at: parsedInput.plannedPickupAt,
    p_planned_delivery_at: parsedInput.plannedDeliveryAt,
    p_allocated_quantity: parsedInput.allocatedQuantity,
    p_allocated_weight_kg: parsedInput.allocatedWeightKg,
    p_allocated_volume_cbm: parsedInput.allocatedVolumeCbm,
    p_basis_quantity: parsedInput.basisQuantity,
    p_basis_weight_kg: parsedInput.basisWeightKg,
    p_basis_volume_cbm: parsedInput.basisVolumeCbm,
    p_split_reason: parsedInput.splitReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** draft -> confirmed, gated by OPS:Edit. Optimistic-concurrency-checked (expectedVersion). */
export async function confirmShipmentOrder(client: ShipmentOrderMutationRpcClient, input: ConfirmShipmentOrderInput): Promise<ShipmentOrder> {
  const parsedInput = ConfirmShipmentOrderInputSchema.parse(input);
  return callAndParseShipmentOrder(client, "confirm_shipment_order", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** draft/confirmed -> cancelled, mandatory reason. Releases this Shipment Order's own allocation from the job's running balance. */
export async function cancelShipmentOrder(client: ShipmentOrderMutationRpcClient, input: CancelShipmentOrderInput): Promise<ShipmentOrder> {
  const parsedInput = CancelShipmentOrderInputSchema.parse(input);
  return callAndParseShipmentOrder(client, "cancel_shipment_order", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
