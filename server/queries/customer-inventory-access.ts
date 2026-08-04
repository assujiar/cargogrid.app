/**
 * Customer Inventory Access read queries (ATW-023, CG-S10-ATW-023). Thin, typed
 * wrappers around every read RPC in supabase/migrations/
 * 20260730310000_create_advanced_tms_customer_inventory_access.sql except app.export_
 * customer_inventory_snapshot (an audited side effect -- see
 * server/mutations/customer-inventory-access.ts).
 *
 * Every RPC here composes app.evaluate_customer_inventory_access/app.resolve_
 * customer_owner_account_scope server-side -- deny-by-default, no OPS/staff RBAC
 * dependency. The two get RPCs raise an identically-shaped `record_not_found` error
 * (errcode no_data_found) whether the target genuinely does not exist or exists but
 * fails the gate (anti-enumeration, migration design note 5) -- callers must not try
 * to distinguish the two from the thrown error's own content.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerInventoryBalance,
  parseCustomerLotIdentity,
  parseCustomerSerialIdentity,
  parseCustomerOutboundOrder,
  parseCustomerOutboundOrderLine,
  parseCustomerInventoryMovementSummary,
  parseCustomerWarehouseEligibility,
  type CustomerInventoryBalance,
  type CustomerLotIdentity,
  type CustomerSerialIdentity,
  type CustomerOutboundOrder,
  type CustomerOutboundOrderLine,
  type CustomerInventoryMovementSummary,
  type CustomerWarehouseEligibility,
  type CustomerOutboundOrderStatus,
  type CustomerIdentityStatus,
} from "../contracts/customer-inventory-access/customer-inventory-access.ts";

export type CustomerInventoryAccessQueryClient = Pick<SupabaseClient, "rpc">;

export class CustomerInventoryAccessQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CustomerInventoryAccessQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Matches the anti-enumerating `record_not_found` prefix every get RPC in this migration raises (design note 5) -- never used to distinguish not-found from forbidden, only to detect that a denial-worthy error occurred at all. */
function isRecordNotFoundError(message: string): boolean {
  return message.startsWith("record_not_found");
}

/**
 * Durable denial audit (Prompt 242 §18 "result count/denial"), issued in a NEW,
 * separate RPC call/transaction after catching a get RPC's own anti-enumerating
 * record_not_found -- resolves migration design note 9's disclosed same-transaction-
 * rollback conflict without weakening anti-enumeration (design note 5): this call
 * always succeeds identically regardless of the real denial cause, so it introduces
 * no new enumeration surface. Best-effort -- a failure here must never mask or
 * replace the original anti-enumerating error the caller is about to see, so any
 * error from this call is swallowed, never re-thrown or surfaced.
 */
async function recordCustomerInventoryAccessDenial(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  resourceType: string,
  resourceId: string,
): Promise<void> {
  try {
    await client.rpc("record_customer_inventory_access_denial", {
      p_tenant_id: tenantId,
      p_actor_auth_user_id: actorAuthUserId,
      p_resource_type: resourceType,
      p_resource_id: resourceId,
    });
  } catch {
    // Best-effort: the original record_not_found error is what the caller must see.
  }
}

/** Common cursor options every list function below accepts -- pass the previous page's last row's own updatedAt/id to advance; omit both for the first page. */
export interface CustomerInventoryCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Single permitted balance row by id. Throws record_not_found (anti-enumerating) if missing or forbidden. */
export async function getCustomerInventoryBalance(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  balanceId: string,
): Promise<CustomerInventoryBalance> {
  const { data, error } = await client.rpc("get_customer_inventory_balance", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_balance_id: balanceId,
  });
  if (error) {
    if (isRecordNotFoundError(error.message)) {
      await recordCustomerInventoryAccessDenial(client, tenantId, actorAuthUserId, "inventory_balance", balanceId);
    }
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerInventoryAccessQueryError("get_customer_inventory_balance returned no row");
  }
  return parseCustomerInventoryBalance(row);
}

/** Bounded (default 50, hard-capped 200 server-side), owner+warehouse-eligibility scoped, excludes all-zero rows, keyset-paginated. */
export async function listCustomerInventoryBalances(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerInventoryCursorOptions & { warehouseId?: string | null; itemMasterId?: string | null },
): Promise<CustomerInventoryBalance[]> {
  const { data, error } = await client.rpc("list_customer_inventory_balances", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_item_master_id: options?.itemMasterId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerInventoryBalance);
}

/** Bounded, owner+warehouse-eligibility scoped tracked-stock attributes (lots), keyset-paginated. Mirrors app.list_customer_serial_identities as a separate function, not unified. */
export async function listCustomerLotIdentities(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerInventoryCursorOptions & {
    warehouseId?: string | null;
    itemMasterId?: string | null;
    ownerAccountId?: string | null;
    statusFilter?: CustomerIdentityStatus | null;
  },
): Promise<CustomerLotIdentity[]> {
  const { data, error } = await client.rpc("list_customer_lot_identities", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_item_master_id: options?.itemMasterId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerLotIdentity);
}

/** Bounded, owner+warehouse-eligibility scoped tracked-stock attributes (serials), keyset-paginated. */
export async function listCustomerSerialIdentities(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerInventoryCursorOptions & {
    warehouseId?: string | null;
    itemMasterId?: string | null;
    ownerAccountId?: string | null;
    statusFilter?: CustomerIdentityStatus | null;
  },
): Promise<CustomerSerialIdentity[]> {
  const { data, error } = await client.rpc("list_customer_serial_identities", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_item_master_id: options?.itemMasterId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerSerialIdentity);
}

/** Single permitted outbound order by id, re-checked against the order's own owner_account_id/warehouse_id. Throws record_not_found (anti-enumerating) if missing or forbidden. */
export async function getCustomerOutboundOrder(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  outboundOrderId: string,
): Promise<CustomerOutboundOrder> {
  const { data, error } = await client.rpc("get_customer_outbound_order", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_outbound_order_id: outboundOrderId,
  });
  if (error) {
    if (isRecordNotFoundError(error.message)) {
      await recordCustomerInventoryAccessDenial(client, tenantId, actorAuthUserId, "outbound_order", outboundOrderId);
    }
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerInventoryAccessQueryError("get_customer_outbound_order returned no row");
  }
  return parseCustomerOutboundOrder(row);
}

/** Every line on one permitted outbound order (re-derives the gate through app.get_customer_outbound_order -- same anti-enumerating record_not_found on a forbidden/missing order). */
export async function listCustomerOutboundOrderLines(
  client: CustomerInventoryAccessQueryClient,
  outboundOrderId: string,
  actorAuthUserId: string,
): Promise<CustomerOutboundOrderLine[]> {
  const { data, error } = await client.rpc("list_customer_outbound_order_lines", {
    p_outbound_order_id: outboundOrderId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerOutboundOrderLine);
}

/** Bounded, owner+warehouse-eligibility scoped outbound order list, keyset-paginated. */
export async function listCustomerOutboundOrders(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerInventoryCursorOptions & { warehouseId?: string | null; statusFilter?: CustomerOutboundOrderStatus | null },
): Promise<CustomerOutboundOrder[]> {
  const { data, error } = await client.rpc("list_customer_outbound_orders", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerOutboundOrder);
}

/** Bounded, owner+warehouse-eligibility scoped movement lineage summary, keyset-paginated on (occurred_at desc, id desc) -- note the cursor's own timestamp field is occurred_at, not updated_at (migration design note 7). */
export async function listCustomerInventoryMovementSummary(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; itemMasterId?: string | null; cursorOccurredAt?: string | null; cursorId?: string | null; limit?: number },
): Promise<CustomerInventoryMovementSummary[]> {
  const { data, error } = await client.rpc("list_customer_inventory_movement_summary", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_item_master_id: options?.itemMasterId ?? null,
    p_cursor_occurred_at: options?.cursorOccurredAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerInventoryMovementSummary);
}

/** The caller's own warehouse eligibility grants (active AND revoked, so they can see why a warehouse disappeared) -- no OPS RBAC gate at all, purely resolved-owner-scope. */
export async function listCustomerWarehouseEligibility(
  client: CustomerInventoryAccessQueryClient,
  tenantId: string,
  actorAuthUserId: string,
): Promise<CustomerWarehouseEligibility[]> {
  const { data, error } = await client.rpc("list_customer_warehouse_eligibility", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CustomerInventoryAccessQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerWarehouseEligibility);
}
