/**
 * Customer Shipment Order read queries (CPL-304, CG-S13-CPL-006). Thin,
 * typed wrappers around every read RPC in supabase/migrations/
 * 20260801050000_create_customer_portal_shipment_order_access.sql, mirroring
 * server/queries/customer-booking-request.ts's own wrapper shape exactly.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerShipmentOrder,
  parseCustomerShipmentChangeRequest,
  type CustomerShipmentOrder,
  type CustomerShipmentChangeRequest,
  type ShipmentOrderStatus,
} from "../contracts/customer-shipment-order/customer-shipment-order.ts";

export type CustomerShipmentOrderQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerShipmentOrderQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerShipmentOrderQueryError extends Error {
  readonly code: CustomerShipmentOrderQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerShipmentOrderQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

export interface CustomerShipmentOrderCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/**
 * Single permitted shipment order by id, a customer-safe projection -- never
 * app.shipment_orders itself. Throws record_not_found (anti-enumerating,
 * errcode no_data_found) whether the id genuinely does not exist, belongs to
 * another tenant, or exists but its own shipper account is outside this
 * identity's resolved scope -- the caller must not try to distinguish the
 * three from the thrown error's own content.
 */
export async function getCustomerShipmentOrder(client: CustomerShipmentOrderQueryClient, tenantId: string, actorAuthUserId: string, shipmentOrderId: string): Promise<CustomerShipmentOrder> {
  const { data, error } = await client.rpc("get_customer_shipment_order", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_shipment_order_id: shipmentOrderId,
  });
  if (error) {
    throw new CustomerShipmentOrderQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new CustomerShipmentOrderQueryError("query_failed: get_customer_shipment_order returned no row");
  }
  return parseCustomerShipmentOrder(row as Record<string, unknown>);
}

/**
 * Keyset-paginated (tenant_id, updated_at desc, id desc), never OFFSET,
 * hard-capped at 200 server-side. Deny-by-default: zero scope or an
 * out-of-scope accountId filter both return an empty array, never an error.
 */
export async function listCustomerShipmentOrders(
  client: CustomerShipmentOrderQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerShipmentOrderCursorOptions & { accountId?: string | null; status?: ShipmentOrderStatus | null },
): Promise<CustomerShipmentOrder[]> {
  const { data, error } = await client.rpc("list_customer_shipment_orders", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_account_id: options?.accountId ?? null,
    p_status: options?.status ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerShipmentOrderQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerShipmentOrder);
}

/**
 * Keyset-paginated list of this identity's own shipment change requests,
 * optionally narrowed to one shipment order. Deny-by-default: zero scope
 * returns an empty array, never an error.
 */
export async function listCustomerShipmentOrderChangeRequests(
  client: CustomerShipmentOrderQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerShipmentOrderCursorOptions & { shipmentOrderId?: string | null },
): Promise<CustomerShipmentChangeRequest[]> {
  const { data, error } = await client.rpc("list_customer_shipment_order_change_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_shipment_order_id: options?.shipmentOrderId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerShipmentOrderQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerShipmentChangeRequest);
}
