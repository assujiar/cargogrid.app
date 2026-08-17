/**
 * Customer Shipment Alert mutation primitives (CPL-306, CG-S13-CPL-008).
 * Thin, typed wrappers around every write RPC in supabase/migrations/
 * 20260801070000_create_customer_portal_shipment_monitoring.sql, mirroring
 * server/mutations/customer-shipment-order.ts's own known-error-code/
 * classifyError/callRpc shape.
 *
 * Both RPCs are idempotent upserts on a natural (tenant, shipment_order,
 * identity, alert_type) key -- neither takes a client-supplied idempotency
 * key, since the natural key already IS the caller's own verified identity
 * plus the explicit target (migration header decision 3).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SubscribeCustomerShipmentAlertInputSchema,
  UnsubscribeCustomerShipmentAlertInputSchema,
  parseCustomerShipmentAlertSubscription,
  type SubscribeCustomerShipmentAlertInput,
  type UnsubscribeCustomerShipmentAlertInput,
  type CustomerShipmentAlertSubscription,
} from "../contracts/customer-shipment-alert/customer-shipment-alert.ts";

export type CustomerShipmentAlertMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CUSTOMER_SHIPMENT_ALERT_KNOWN_MUTATION_ERROR_CODES = ["invalid_alert_type", "shipment_order_not_found", "actor_identity_mismatch"] as const;
export type KnownCustomerShipmentAlertMutationErrorCode = (typeof CUSTOMER_SHIPMENT_ALERT_KNOWN_MUTATION_ERROR_CODES)[number];
export type CustomerShipmentAlertMutationErrorCode = KnownCustomerShipmentAlertMutationErrorCode | "mutation_failed";

export class CustomerShipmentAlertMutationError extends Error {
  readonly code: CustomerShipmentAlertMutationErrorCode;

  constructor(code: CustomerShipmentAlertMutationErrorCode, message: string) {
    super(message);
    this.name = "CustomerShipmentAlertMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CustomerShipmentAlertMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (CUSTOMER_SHIPMENT_ALERT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownCustomerShipmentAlertMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc(client: CustomerShipmentAlertMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<CustomerShipmentAlertSubscription> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new CustomerShipmentAlertMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerShipmentAlertMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parseCustomerShipmentAlertSubscription(row as Record<string, unknown>);
}

/** Idempotent upsert to status=active. Scope-checked against the shipment order's own shipper_account_id, live on every call, before the upsert runs. */
export async function subscribeCustomerShipmentAlert(client: CustomerShipmentAlertMutationRpcClient, input: SubscribeCustomerShipmentAlertInput): Promise<CustomerShipmentAlertSubscription> {
  const v = SubscribeCustomerShipmentAlertInputSchema.parse(input);
  return callRpc(client, "subscribe_customer_shipment_alert", {
    p_tenant_id: v.tenantId,
    p_shipment_order_id: v.shipmentOrderId,
    p_alert_type: v.alertType,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

/** Idempotent upsert to status=unsubscribed -- a no-op-shaped success even when no prior subscription existed. */
export async function unsubscribeCustomerShipmentAlert(client: CustomerShipmentAlertMutationRpcClient, input: UnsubscribeCustomerShipmentAlertInput): Promise<CustomerShipmentAlertSubscription> {
  const v = UnsubscribeCustomerShipmentAlertInputSchema.parse(input);
  return callRpc(client, "unsubscribe_customer_shipment_alert", {
    p_tenant_id: v.tenantId,
    p_shipment_order_id: v.shipmentOrderId,
    p_alert_type: v.alertType,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}
