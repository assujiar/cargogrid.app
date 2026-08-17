/**
 * Customer Portal Warehouse Order and Order Fulfillment Visibility read
 * queries (CPL-310, CG-S13-CPL-012). Thin, typed wrappers around every RPC in
 * supabase/migrations/20260801110000_create_customer_portal_warehouse_order_
 * fulfillment_visibility.sql, mirroring server/queries/customer-inventory-
 * access.ts's (ATW-023) own wrapper shape exactly -- including the same
 * denial-audit follow-up call convention -- except every RPC here is gated
 * via app.resolve_customer_account_scope (CPL-300's widened resolver), so an
 * account granted only through CPL-300's new multi-account grant table is
 * visible here (ISS-2026-117 fix), where the ATW-023 wrappers would wrongly
 * see nothing for that account.
 *
 * The get RPC raises an anti-enumerating `record_not_found` error (errcode
 * no_data_found) whether the target genuinely does not exist or exists but
 * fails the gate -- callers must not try to distinguish the two from the
 * thrown error's own content. `.code` (mirrors server/queries/customer-
 * shipment-order.ts's own newer convention) lets a caller branch on
 * record_not_found specifically, e.g. to render a plain 404.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerWarehouseOrder,
  parseCustomerWarehouseOrderLine,
  type CustomerWarehouseOrder,
  type CustomerWarehouseOrderLine,
  type CustomerWarehouseOrderStatus,
} from "../contracts/customer-portal-warehouse-order/customer-portal-warehouse-order.ts";

export type CustomerPortalWarehouseOrderQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["record_not_found", "actor_identity_mismatch", "invalid_cursor"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type CustomerPortalWarehouseOrderQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class CustomerPortalWarehouseOrderQueryError extends Error {
  readonly code: CustomerPortalWarehouseOrderQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalWarehouseOrderQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/**
 * Durable denial audit, issued in a NEW, separate RPC call/transaction after
 * catching the get RPC's own anti-enumerating record_not_found -- reuses
 * app.record_customer_inventory_access_denial (ATW-023) exactly as-is, the
 * SAME resource_type ('outbound_order') ATW-023's own db-test already uses
 * for this resource. Best-effort -- a failure here must never mask or
 * replace the original anti-enumerating error the caller is about to see, so
 * any error from this call is swallowed, never re-thrown or surfaced.
 */
async function recordCustomerPortalWarehouseOrderAccessDenial(
  client: CustomerPortalWarehouseOrderQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  resourceId: string,
): Promise<void> {
  try {
    await client.rpc("record_customer_inventory_access_denial", {
      p_tenant_id: tenantId,
      p_actor_auth_user_id: actorAuthUserId,
      p_resource_type: "outbound_order",
      p_resource_id: resourceId,
    });
  } catch {
    // Best-effort: the original record_not_found error is what the caller must see.
  }
}

/** Common cursor options app.list_customer_portal_outbound_orders accepts -- pass the previous page's last row's own updatedAt/id to advance; omit both for the first page. */
export interface CustomerPortalWarehouseOrderCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Single permitted outbound order by id. Throws record_not_found (anti-enumerating, .code === "record_not_found") if missing or forbidden; also records a durable denial audit on that path. */
export async function getCustomerPortalOutboundOrder(
  client: CustomerPortalWarehouseOrderQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  outboundOrderId: string,
): Promise<CustomerWarehouseOrder> {
  const { data, error } = await client.rpc("get_customer_portal_outbound_order", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_outbound_order_id: outboundOrderId,
  });
  if (error) {
    const wrapped = new CustomerPortalWarehouseOrderQueryError(error.message);
    if (wrapped.code === "record_not_found") {
      await recordCustomerPortalWarehouseOrderAccessDenial(client, tenantId, actorAuthUserId, outboundOrderId);
    }
    throw wrapped;
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalWarehouseOrderQueryError("query_failed: get_customer_portal_outbound_order returned no row");
  }
  return parseCustomerWarehouseOrder(row);
}

/** Bounded (default 50, hard-capped 200 server-side), owner+warehouse-eligibility scoped, keyset-paginated. */
export async function listCustomerPortalOutboundOrders(
  client: CustomerPortalWarehouseOrderQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerPortalWarehouseOrderCursorOptions & { warehouseId?: string | null; statusFilter?: CustomerWarehouseOrderStatus | null },
): Promise<CustomerWarehouseOrder[]> {
  const { data, error } = await client.rpc("list_customer_portal_outbound_orders", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalWarehouseOrderQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerWarehouseOrder);
}

/** Lines for a single permitted order, ordered by line_number. Reuses app.get_customer_portal_outbound_order's own gate internally -- record_not_found (anti-enumerating) if the order is missing or forbidden. Deliberately takes no tenantId (mirrors the RPC's own tenant-id-less signature, ATW-023 precedent). */
export async function listCustomerPortalOutboundOrderLines(
  client: CustomerPortalWarehouseOrderQueryClient,
  actorAuthUserId: string,
  outboundOrderId: string,
): Promise<CustomerWarehouseOrderLine[]> {
  const { data, error } = await client.rpc("list_customer_portal_outbound_order_lines", {
    p_outbound_order_id: outboundOrderId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CustomerPortalWarehouseOrderQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerWarehouseOrderLine);
}
