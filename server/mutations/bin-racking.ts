/**
 * Bin and Racking mutation primitives (ATW-230, CG-S10-ATW-011). Thin, typed wrappers
 * around app.create_warehouse_location/app.update_warehouse_location/
 * app.move_warehouse_location/app.set_warehouse_location_status
 * (supabase/migrations/20260730150000_create_advanced_tms_bin_racking.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateWarehouseLocationInputSchema,
  UpdateWarehouseLocationInputSchema,
  MoveWarehouseLocationInputSchema,
  SetWarehouseLocationStatusInputSchema,
  parseWarehouseLocation,
  type CreateWarehouseLocationInput,
  type UpdateWarehouseLocationInput,
  type MoveWarehouseLocationInput,
  type SetWarehouseLocationStatusInput,
  type WarehouseLocation,
} from "../contracts/bin-racking/bin-racking.ts";

export type BinRackingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const BIN_RACKING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_code",
  "invalid_name",
  "invalid_location_type",
  "warehouse_not_found",
  "warehouse_not_active",
  "incompatible_zone",
  "invalid_capacity",
  "location_code_conflict",
  "duplicate_barcode",
  "location_not_found",
  "stale_version",
  "location_not_draft",
  "cross_tenant_parent",
  "cross_warehouse_parent",
  "warehouse_location_cycle",
  "warehouse_location_depth_exceeded",
  "warehouse_location_parent_not_found",
  "invalid_status",
  "reason_required",
  "location_has_active_children",
  "invalid_barcode",
] as const;
type KnownBinRackingMutationErrorCode = (typeof BIN_RACKING_KNOWN_MUTATION_ERROR_CODES)[number];
export type BinRackingMutationErrorCode = KnownBinRackingMutationErrorCode | "mutation_failed" | "invalid_response";

export class BinRackingMutationError extends Error {
  readonly code: BinRackingMutationErrorCode;

  constructor(code: BinRackingMutationErrorCode, message: string) {
    super(message);
    this.name = "BinRackingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): BinRackingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (BIN_RACKING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownBinRackingMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseLocationResponse(data: unknown, rpcName: string): WarehouseLocation {
  const row = firstRow(data);
  if (!row) {
    throw new BinRackingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWarehouseLocation(row);
}

export async function createWarehouseLocation(client: BinRackingMutationRpcClient, input: CreateWarehouseLocationInput): Promise<WarehouseLocation> {
  const parsedInput = CreateWarehouseLocationInputSchema.parse(input);
  const { data, error } = await client.rpc("create_warehouse_location", {
    p_warehouse_id: parsedInput.warehouseId,
    p_zone_id: parsedInput.zoneId,
    p_parent_id: parsedInput.parentId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_location_type: parsedInput.locationType,
    p_sequence: parsedInput.sequence,
    p_capacity_value: parsedInput.capacityValue,
    p_capacity_uom: parsedInput.capacityUom,
    p_environment: parsedInput.environment,
    p_restrictions: parsedInput.restrictions,
    p_barcode: parsedInput.barcode,
    p_pick_enabled: parsedInput.pickEnabled,
    p_putaway_enabled: parsedInput.putawayEnabled,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BinRackingMutationError(classifyError(error.message), error.message);
  }
  return parseLocationResponse(data, "create_warehouse_location");
}

export async function updateWarehouseLocation(client: BinRackingMutationRpcClient, input: UpdateWarehouseLocationInput): Promise<WarehouseLocation> {
  const parsedInput = UpdateWarehouseLocationInputSchema.parse(input);
  const { data, error } = await client.rpc("update_warehouse_location", {
    p_location_id: parsedInput.locationId,
    p_name: parsedInput.name,
    p_sequence: parsedInput.sequence,
    p_capacity_value: parsedInput.capacityValue,
    p_capacity_uom: parsedInput.capacityUom,
    p_environment: parsedInput.environment,
    p_restrictions: parsedInput.restrictions,
    p_barcode: parsedInput.barcode,
    p_pick_enabled: parsedInput.pickEnabled,
    p_putaway_enabled: parsedInput.putawayEnabled,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BinRackingMutationError(classifyError(error.message), error.message);
  }
  return parseLocationResponse(data, "update_warehouse_location");
}

export async function moveWarehouseLocation(client: BinRackingMutationRpcClient, input: MoveWarehouseLocationInput): Promise<WarehouseLocation> {
  const parsedInput = MoveWarehouseLocationInputSchema.parse(input);
  const { data, error } = await client.rpc("move_warehouse_location", {
    p_location_id: parsedInput.locationId,
    p_new_parent_id: parsedInput.newParentId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BinRackingMutationError(classifyError(error.message), error.message);
  }
  return parseLocationResponse(data, "move_warehouse_location");
}

export async function setWarehouseLocationStatus(client: BinRackingMutationRpcClient, input: SetWarehouseLocationStatusInput): Promise<WarehouseLocation> {
  const parsedInput = SetWarehouseLocationStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_warehouse_location_status", {
    p_location_id: parsedInput.locationId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BinRackingMutationError(classifyError(error.message), error.message);
  }
  return parseLocationResponse(data, "set_warehouse_location_status");
}
