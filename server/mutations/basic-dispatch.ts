/**
 * Basic Dispatch mutation primitives (OPS-175, CG-S8-OPS-009). Thin, typed wrappers
 * around app.dispatch_shipment_order / app.bulk_dispatch_shipment_orders
 * (supabase/migrations/20260727160000_create_operations_basic_dispatch.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  DispatchShipmentOrderInputSchema,
  BulkDispatchShipmentOrdersInputSchema,
  parseDispatchCommand,
  parseBulkDispatchResultRow,
  type DispatchShipmentOrderInput,
  type BulkDispatchShipmentOrdersInput,
  type DispatchCommand,
  type BulkDispatchResultRow,
} from "../contracts/basic-dispatch/basic-dispatch.ts";

export type BasicDispatchMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const BASIC_DISPATCH_KNOWN_MUTATION_ERROR_CODES = [
  "idempotency_key_required",
  "shipment_order_not_found",
  "dispatch_not_ready",
  "invalid_transition",
  "stale_version",
  "bulk_empty",
  "bulk_too_large",
  "insufficient_authority",
] as const;
type KnownBasicDispatchMutationErrorCode = (typeof BASIC_DISPATCH_KNOWN_MUTATION_ERROR_CODES)[number];
export type BasicDispatchMutationErrorCode = KnownBasicDispatchMutationErrorCode | "mutation_failed" | "invalid_response";

export class BasicDispatchMutationError extends Error {
  readonly code: BasicDispatchMutationErrorCode;

  constructor(code: BasicDispatchMutationErrorCode, message: string) {
    super(message);
    this.name = "BasicDispatchMutationError";
    this.code = code;
  }
}

function classifyError(message: string): BasicDispatchMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (BASIC_DISPATCH_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownBasicDispatchMutationErrorCode)
    : "mutation_failed";
}

/** The one validated dispatch command -- idempotent on (shipmentOrderId, idempotencyKey): a genuine retry returns the same prior command row rather than re-evaluating readiness. */
export async function dispatchShipmentOrder(client: BasicDispatchMutationRpcClient, input: DispatchShipmentOrderInput): Promise<DispatchCommand> {
  const parsedInput = DispatchShipmentOrderInputSchema.parse(input);
  const { data, error } = await client.rpc("dispatch_shipment_order", {
    p_shipment_order_id: parsedInput.shipmentOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BasicDispatchMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BasicDispatchMutationError("invalid_response", "dispatch_shipment_order returned no row");
  }
  return parseDispatchCommand(data as Record<string, unknown>);
}

/** Bounded at 50 ids; each id is independently permission/record-scope/readiness-rechecked and independently idempotent -- one record's failure never aborts another's. */
export async function bulkDispatchShipmentOrders(
  client: BasicDispatchMutationRpcClient,
  input: BulkDispatchShipmentOrdersInput,
): Promise<BulkDispatchResultRow[]> {
  const parsedInput = BulkDispatchShipmentOrdersInputSchema.parse(input);
  const { data, error } = await client.rpc("bulk_dispatch_shipment_orders", {
    p_shipment_order_ids: parsedInput.shipmentOrderIds,
    p_idempotency_key_prefix: parsedInput.idempotencyKeyPrefix,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BasicDispatchMutationError(classifyError(error.message), error.message);
  }
  if (!Array.isArray(data)) {
    throw new BasicDispatchMutationError("invalid_response", "bulk_dispatch_shipment_orders returned a non-array result");
  }
  return data.map((row: Record<string, unknown>) => parseBulkDispatchResultRow(row));
}
