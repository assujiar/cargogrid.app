/**
 * Customer Portal Warehouse Inventory Visibility read queries (CPL-309,
 * CG-S13-CPL-011). Thin, typed wrappers around every RPC in supabase/migrations/
 * 20260801100000_create_customer_portal_warehouse_inventory_visibility.sql,
 * mirroring server/queries/customer-inventory-access.ts's (ATW-023) own wrapper
 * shape exactly -- including the same denial-audit follow-up call convention --
 * except every RPC here is gated via app.resolve_customer_account_scope (CPL-300's
 * widened resolver), so an account granted only through CPL-300's new multi-
 * account grant table is visible here (ISS-2026-117 fix), where the ATW-023
 * wrappers would wrongly see nothing for that account.
 *
 * The get RPC raises an anti-enumerating `record_not_found` error (errcode
 * no_data_found) whether the target genuinely does not exist or exists but fails
 * the gate -- callers must not try to distinguish the two from the thrown error's
 * own content.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCustomerPortalInventoryBalance,
  parseCustomerPortalWarehouseEligibility,
  type CustomerPortalInventoryBalance,
  type CustomerPortalWarehouseEligibility,
} from "../contracts/customer-portal-inventory/customer-portal-inventory.ts";

export type CustomerPortalInventoryQueryClient = Pick<SupabaseClient, "rpc">;

export class CustomerPortalInventoryQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CustomerPortalInventoryQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Matches the anti-enumerating `record_not_found` prefix the get RPC raises -- never used to distinguish not-found from forbidden, only to detect that a denial-worthy error occurred at all. */
function isRecordNotFoundError(message: string): boolean {
  return message.startsWith("record_not_found");
}

/**
 * Durable denial audit, issued in a NEW, separate RPC call/transaction after
 * catching the get RPC's own anti-enumerating record_not_found -- reuses
 * app.record_customer_inventory_access_denial (ATW-023) exactly as-is, the same
 * generic actor/resource-type/resource-id audit primitive server/queries/
 * customer-inventory-access.ts already calls this same way. Best-effort -- a
 * failure here must never mask or replace the original anti-enumerating error the
 * caller is about to see, so any error from this call is swallowed, never
 * re-thrown or surfaced.
 */
async function recordCustomerPortalInventoryAccessDenial(
  client: CustomerPortalInventoryQueryClient,
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

/** Common cursor options app.list_customer_portal_inventory_balances accepts -- pass the previous page's last row's own updatedAt/id to advance; omit both for the first page. */
export interface CustomerPortalInventoryCursorOptions {
  cursorUpdatedAt?: string | null;
  cursorId?: string | null;
  limit?: number;
}

/** Single permitted balance row by id. Throws record_not_found (anti-enumerating) if missing or forbidden; also records a durable denial audit on that path. */
export async function getCustomerPortalInventoryBalance(
  client: CustomerPortalInventoryQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  balanceId: string,
): Promise<CustomerPortalInventoryBalance> {
  const { data, error } = await client.rpc("get_customer_portal_inventory_balance", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_balance_id: balanceId,
  });
  if (error) {
    if (isRecordNotFoundError(error.message)) {
      await recordCustomerPortalInventoryAccessDenial(client, tenantId, actorAuthUserId, "inventory_balance", balanceId);
    }
    throw new CustomerPortalInventoryQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new CustomerPortalInventoryQueryError("get_customer_portal_inventory_balance returned no row");
  }
  return parseCustomerPortalInventoryBalance(row);
}

/** Bounded (default 50, hard-capped 200 server-side), owner+warehouse-eligibility scoped, excludes all-zero rows, keyset-paginated. */
export async function listCustomerPortalInventoryBalances(
  client: CustomerPortalInventoryQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: CustomerPortalInventoryCursorOptions & { warehouseId?: string | null; itemMasterId?: string | null },
): Promise<CustomerPortalInventoryBalance[]> {
  const { data, error } = await client.rpc("list_customer_portal_inventory_balances", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_item_master_id: options?.itemMasterId ?? null,
    p_cursor_updated_at: options?.cursorUpdatedAt ?? null,
    p_cursor_id: options?.cursorId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new CustomerPortalInventoryQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalInventoryBalance);
}

/** The caller's own warehouse eligibility grants (active AND revoked, so they can see why a warehouse disappeared) -- no OPS RBAC gate at all, purely resolved-owner-scope. Drives the portal UI's warehouse/site filter. */
export async function listCustomerPortalWarehouseEligibility(
  client: CustomerPortalInventoryQueryClient,
  tenantId: string,
  actorAuthUserId: string,
): Promise<CustomerPortalWarehouseEligibility[]> {
  const { data, error } = await client.rpc("list_customer_portal_warehouse_eligibility", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CustomerPortalInventoryQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCustomerPortalWarehouseEligibility);
}
