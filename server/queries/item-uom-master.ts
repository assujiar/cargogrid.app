/**
 * Item/SKU and UOM Master read queries (ATW-011A, CG-S10-ATW-011A). Thin, typed
 * wrappers around app.get_item_master/app.resolve_item_master_by_code/
 * app.list_item_masters/app.validate_uom_code/app.convert_uom_quantity
 * (supabase/migrations/20260730160000_create_advanced_tms_item_uom_master.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseItemMaster, type ItemMaster, type ItemMasterStatus } from "../contracts/item-uom-master/item-uom-master.ts";

export type ItemUomMasterQueryClient = Pick<SupabaseClient, "rpc">;

export class ItemUomMasterQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ItemUomMasterQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-row read by id, RBAC-gated (OPS:View). */
export async function getItemMaster(client: ItemUomMasterQueryClient, itemMasterId: string, actorAuthUserId: string): Promise<ItemMaster> {
  const { data, error } = await client.rpc("get_item_master", { p_item_master_id: itemMasterId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ItemUomMasterQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ItemUomMasterQueryError("get_item_master returned no row");
  }
  return parseItemMaster(row);
}

/** Exact-code lookup within one (tenant, owner) -- the resolution path Prompt 231 (WMS Inbound) is expected to call when inheriting an item identity from a source shipment/customer reference. */
export async function resolveItemMasterByCode(
  client: ItemUomMasterQueryClient,
  tenantId: string,
  ownerAccountId: string,
  code: string,
  actorAuthUserId: string,
): Promise<ItemMaster> {
  const { data, error } = await client.rpc("resolve_item_master_by_code", {
    p_tenant_id: tenantId,
    p_owner_account_id: ownerAccountId,
    p_code: code,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new ItemUomMasterQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new ItemUomMasterQueryError("resolve_item_master_by_code returned no row");
  }
  return parseItemMaster(row);
}

/** Bounded (default 50, hard-capped 200 server-side), tenant-wide, optionally narrowed to one owner_account_id/status/search term. */
export async function listItemMasters(
  client: ItemUomMasterQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { ownerAccountId?: string | null; statusFilter?: ItemMasterStatus | null; search?: string | null; limit?: number },
): Promise<ItemMaster[]> {
  const { data, error } = await client.rpc("list_item_masters", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_search: options?.search ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new ItemUomMasterQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseItemMaster);
}

/** True only for a registered, active UOM code. */
export async function validateUomCode(client: ItemUomMasterQueryClient, code: string): Promise<boolean> {
  const { data, error } = await client.rpc("validate_uom_code", { p_code: code });
  if (error) {
    throw new ItemUomMasterQueryError(error.message);
  }
  return Boolean(data);
}

/** Exact-decimal quantity conversion via app.uom_conversions (direct or inverse factor). Rejects (throws) rather than guessing when no registered path exists between the two codes. */
export async function convertUomQuantity(client: ItemUomMasterQueryClient, quantity: number, fromUomCode: string, toUomCode: string): Promise<number> {
  const { data, error } = await client.rpc("convert_uom_quantity", {
    p_quantity: quantity,
    p_from_uom_code: fromUomCode,
    p_to_uom_code: toUomCode,
  });
  if (error) {
    throw new ItemUomMasterQueryError(error.message);
  }
  return Number(data);
}
