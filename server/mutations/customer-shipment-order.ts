/**
 * Customer Shipment Order mutation primitives (CPL-304, CG-S13-CPL-006).
 * Thin, typed wrappers around every write RPC in supabase/migrations/
 * 20260801050000_create_customer_portal_shipment_order_access.sql, mirroring
 * server/mutations/customer-booking-request.ts's own known-error-code/
 * classifyError/callRpc shape.
 *
 * app.respond_to_customer_shipment_order_change_request is the ONE
 * staff-gated (OPS:Edit) function here -- called through the ordinary
 * RLS-scoped `authenticated` client exactly like every other export, since
 * the RPC itself is what enforces the authority split, not the transport.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RequestCustomerShipmentOrderChangeInputSchema,
  RespondToCustomerShipmentOrderChangeRequestInputSchema,
  parseCustomerShipmentChangeRequest,
  type RequestCustomerShipmentOrderChangeInput,
  type RespondToCustomerShipmentOrderChangeRequestInput,
  type CustomerShipmentChangeRequest,
} from "../contracts/customer-shipment-order/customer-shipment-order.ts";

export type CustomerShipmentOrderMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_SHIPMENT_ORDER_KNOWN_MUTATION_ERROR_CODES = [
  "invalid_request_type",
  "details_required",
  "shipment_order_not_found",
  "change_request_not_found",
  "invalid_status",
  "staff_response_required",
  "invalid_transition",
  "stale_version",
  "insufficient_authority",
  "actor_identity_mismatch",
] as const;
export type KnownCustomerShipmentOrderMutationErrorCode = (typeof CUSTOMER_SHIPMENT_ORDER_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerShipmentOrderMutationErrorCode = KnownCustomerShipmentOrderMutationErrorCode | "mutation_failed";

export class CustomerShipmentOrderMutationError extends Error {
  readonly code: CustomerShipmentOrderMutationErrorCode;

  constructor(code: CustomerShipmentOrderMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerShipmentOrderMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerShipmentOrderMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_SHIPMENT_ORDER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerShipmentOrderMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerShipmentOrderMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerShipmentChangeRequest> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerShipmentOrderMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerShipmentOrderMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerShipmentChangeRequest(row as Record<string, unknown>);
}

/** Creates a submitted "request a change" record against a shipment order in this identity's resolved scope. account_id is derived server-side from the shipment order's own shipper_account_id -- never supplied here. Idempotent on (tenantId, idempotencyKey) when a key is supplied. Never touches app.shipment_orders itself. */
export async function requestCustomerShipmentOrderChange(client: CustomerShipmentOrderMutationRpcClient, input: RequestCustomerShipmentOrderChangeInput): Promise<CustomerShipmentChangeRequest> {
  const v = RequestCustomerShipmentOrderChangeInputSchema.parse(input);
  return callRpc(client, "request_customer_shipment_order_change", {
    p_tenant_id: v.tenantId,
    p_shipment_order_id: v.shipmentOrderId,
    p_request_type: v.requestType,
    p_details: v.details,
    p_idempotency_key: v.idempotencyKey ?? null,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Staff-only (OPS:Edit) response/resolution -- submitted -> acknowledged|resolved|rejected, or acknowledged -> resolved|rejected. Mandatory non-empty staffResponse. Optimistic concurrency (staleVersion); idempotent only for a retry landing on the exact same target status and response text. */
export async function respondToCustomerShipmentOrderChangeRequest(
  client: CustomerShipmentOrderMutationRpcClient,
  input: RespondToCustomerShipmentOrderChangeRequestInput,
): Promise<CustomerShipmentChangeRequest> {
  const v = RespondToCustomerShipmentOrderChangeRequestInputSchema.parse(input);
  return callRpc(client, "respond_to_customer_shipment_order_change_request", {
    p_change_request_id: v.changeRequestId,
    p_expected_version: v.expectedVersion,
    p_to_status: v.toStatus,
    p_staff_response: v.staffResponse,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
