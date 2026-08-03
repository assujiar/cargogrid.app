/**
 * Item/SKU and UOM Master mutation primitives (ATW-011A, CG-S10-ATW-011A). Thin,
 * typed wrappers around app.create_item_master/app.update_item_master/
 * app.set_item_master_status
 * (supabase/migrations/20260730160000_create_advanced_tms_item_uom_master.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateItemMasterInputSchema,
  UpdateItemMasterInputSchema,
  SetItemMasterStatusInputSchema,
  parseItemMaster,
  type CreateItemMasterInput,
  type UpdateItemMasterInput,
  type SetItemMasterStatusInput,
  type ItemMaster,
} from "../contracts/item-uom-master/item-uom-master.ts";

export type ItemUomMasterMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ITEM_UOM_MASTER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_code",
  "invalid_name",
  "owner_account_not_found",
  "invalid_base_uom",
  "item_master_not_found",
  "stale_version",
  "invalid_status",
  "invalid_reason",
] as const;
type KnownItemUomMasterMutationErrorCode = (typeof ITEM_UOM_MASTER_KNOWN_MUTATION_ERROR_CODES)[number];
export type ItemUomMasterMutationErrorCode = KnownItemUomMasterMutationErrorCode | "mutation_failed" | "invalid_response";

export class ItemUomMasterMutationError extends Error {
  readonly code: ItemUomMasterMutationErrorCode;

  constructor(code: ItemUomMasterMutationErrorCode, message: string) {
    super(message);
    this.name = "ItemUomMasterMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ItemUomMasterMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ITEM_UOM_MASTER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownItemUomMasterMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseItemMasterResponse(data: unknown, rpcName: string): ItemMaster {
  const row = firstRow(data);
  if (!row) {
    throw new ItemUomMasterMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseItemMaster(row);
}

/** Idempotent on (tenant_id, owner_account_id, code) -- a same-code retry under the same owner returns the identical row. The identical code under a different owner_account_id in the same tenant is a distinct, legal row. */
export async function createItemMaster(client: ItemUomMasterMutationRpcClient, input: CreateItemMasterInput): Promise<ItemMaster> {
  const parsedInput = CreateItemMasterInputSchema.parse(input);
  const { data, error } = await client.rpc("create_item_master", {
    p_tenant_id: parsedInput.tenantId,
    p_owner_account_id: parsedInput.ownerAccountId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_base_uom_code: parsedInput.baseUomCode,
    p_lot_controlled: parsedInput.lotControlled,
    p_serial_controlled: parsedInput.serialControlled,
    p_expiry_controlled: parsedInput.expiryControlled,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  }
  return parseItemMasterResponse(data, "create_item_master");
}

/** Mutable fields only -- code, tenant_id, owner_account_id and base_uom_code are immutable once created. Optimistic-concurrency gated (record_version). */
export async function updateItemMaster(client: ItemUomMasterMutationRpcClient, input: UpdateItemMasterInput): Promise<ItemMaster> {
  const parsedInput = UpdateItemMasterInputSchema.parse(input);
  const { data, error } = await client.rpc("update_item_master", {
    p_item_master_id: parsedInput.itemMasterId,
    p_name: parsedInput.name,
    p_description: parsedInput.description,
    p_lot_controlled: parsedInput.lotControlled,
    p_serial_controlled: parsedInput.serialControlled,
    p_expiry_controlled: parsedInput.expiryControlled,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  }
  return parseItemMasterResponse(data, "update_item_master");
}

/** A reason is required to deactivate; a same-status transition is a no-op returning the current row. Does not check for referencing inbound/receiving/ledger/lot rows -- none exist yet at this checkpoint (disclosed, ATW-231 or whichever future capability first references an item_master row is obligated to wire that check). */
export async function setItemMasterStatus(client: ItemUomMasterMutationRpcClient, input: SetItemMasterStatusInput): Promise<ItemMaster> {
  const parsedInput = SetItemMasterStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_item_master_status", {
    p_item_master_id: parsedInput.itemMasterId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ItemUomMasterMutationError(classifyError(error.message), error.message);
  }
  return parseItemMasterResponse(data, "set_item_master_status");
}
