/**
 * Inventory Ledger read queries (ATW-015, CG-S10-ATW-015). Thin, typed wrappers
 * around app.get_inventory_balance/app.list_inventory_balances/
 * app.list_inventory_movements/app.list_inventory_movement_lines
 * (supabase/migrations/20260730190000_create_advanced_tms_inventory_ledger.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseInventoryBalance,
  parseInventoryMovement,
  parseInventoryMovementLine,
  type InventoryBalance,
  type InventoryMovement,
  type InventoryMovementLine,
  type InventoryMovementType,
  type InventorySourceType,
} from "../contracts/inventory-ledger/inventory-ledger.ts";

export type InventoryLedgerQueryClient = Pick<SupabaseClient, "rpc">;

export class InventoryLedgerQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "InventoryLedgerQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** Single-dimension balance read, RBAC- and record-scope-gated. */
export async function getInventoryBalance(
  client: InventoryLedgerQueryClient,
  params: {
    tenantId: string;
    warehouseId: string;
    ownerAccountId: string;
    itemMasterId: string;
    locationId: string;
    lotNumber?: string | null;
    serialNumber?: string | null;
    status: string;
  },
  actorAuthUserId: string,
): Promise<InventoryBalance> {
  const { data, error } = await client.rpc("get_inventory_balance", {
    p_tenant_id: params.tenantId,
    p_warehouse_id: params.warehouseId,
    p_owner_account_id: params.ownerAccountId,
    p_item_master_id: params.itemMasterId,
    p_location_id: params.locationId,
    p_lot_number: params.lotNumber ?? null,
    p_serial_number: params.serialNumber ?? null,
    p_status: params.status,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new InventoryLedgerQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new InventoryLedgerQueryError("get_inventory_balance returned no row");
  }
  return parseInventoryBalance(row);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped by warehouse, excludes all-zero rows. */
export async function listInventoryBalances(
  client: InventoryLedgerQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; ownerAccountId?: string | null; itemMasterId?: string | null; limit?: number },
): Promise<InventoryBalance[]> {
  const { data, error } = await client.rpc("list_inventory_balances", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_item_master_id: options?.itemMasterId ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new InventoryLedgerQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseInventoryBalance);
}

/** Bounded (default 50, hard-capped 200 server-side), record-scoped by warehouse. */
export async function listInventoryMovements(
  client: InventoryLedgerQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { warehouseId?: string | null; movementType?: InventoryMovementType | null; sourceType?: InventorySourceType | null; limit?: number },
): Promise<InventoryMovement[]> {
  const { data, error } = await client.rpc("list_inventory_movements", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_warehouse_id: options?.warehouseId ?? null,
    p_movement_type: options?.movementType ?? null,
    p_source_type: options?.sourceType ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new InventoryLedgerQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseInventoryMovement);
}

/** Every line on one movement, RBAC- and record-scope-gated via the movement's own warehouse. */
export async function listInventoryMovementLines(client: InventoryLedgerQueryClient, movementId: string, actorAuthUserId: string): Promise<InventoryMovementLine[]> {
  const { data, error } = await client.rpc("list_inventory_movement_lines", { p_movement_id: movementId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new InventoryLedgerQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseInventoryMovementLine);
}
