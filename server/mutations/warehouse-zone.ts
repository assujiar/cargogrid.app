/**
 * Warehouse and Zone mutation primitives (ATW-229, CG-S10-ATW-010). Thin, typed
 * wrappers around app.create_warehouse/app.update_warehouse/app.set_warehouse_status/
 * app.grant_warehouse_customer_eligibility/app.revoke_warehouse_customer_eligibility/
 * app.create_warehouse_zone/app.update_warehouse_zone/app.set_warehouse_zone_status
 * (supabase/migrations/20260730140000_create_advanced_tms_warehouse_zone.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateWarehouseInputSchema,
  UpdateWarehouseInputSchema,
  SetWarehouseStatusInputSchema,
  GrantWarehouseCustomerEligibilityInputSchema,
  RevokeWarehouseCustomerEligibilityInputSchema,
  CreateWarehouseZoneInputSchema,
  UpdateWarehouseZoneInputSchema,
  SetWarehouseZoneStatusInputSchema,
  parseWarehouse,
  parseWarehouseZone,
  parseWarehouseCustomerEligibility,
  type CreateWarehouseInput,
  type UpdateWarehouseInput,
  type SetWarehouseStatusInput,
  type GrantWarehouseCustomerEligibilityInput,
  type RevokeWarehouseCustomerEligibilityInput,
  type CreateWarehouseZoneInput,
  type UpdateWarehouseZoneInput,
  type SetWarehouseZoneStatusInput,
  type Warehouse,
  type WarehouseZone,
  type WarehouseCustomerEligibility,
} from "../contracts/warehouse-zone/warehouse-zone.ts";

export type WarehouseZoneMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WAREHOUSE_ZONE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_code",
  "invalid_name",
  "org_unit_not_found",
  "invalid_timezone",
  "warehouse_code_conflict",
  "warehouse_not_found",
  "stale_version",
  "invalid_status",
  "reason_required",
  "warehouse_has_active_zones",
  "warehouse_has_active_locations",
  "zone_has_active_locations",
  "account_not_found",
  "eligibility_not_found",
  "invalid_transition",
  "invalid_zone_type",
  "warehouse_not_active",
  "invalid_effective_window",
  "invalid_capacity",
  "zone_code_conflict",
  "zone_not_found",
] as const;
type KnownWarehouseZoneMutationErrorCode = (typeof WAREHOUSE_ZONE_KNOWN_MUTATION_ERROR_CODES)[number];
export type WarehouseZoneMutationErrorCode = KnownWarehouseZoneMutationErrorCode | "mutation_failed" | "invalid_response";

export class WarehouseZoneMutationError extends Error {
  readonly code: WarehouseZoneMutationErrorCode;

  constructor(code: WarehouseZoneMutationErrorCode, message: string) {
    super(message);
    this.name = "WarehouseZoneMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WarehouseZoneMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WAREHOUSE_ZONE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWarehouseZoneMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseWarehouseResponse(data: unknown, rpcName: string): Warehouse {
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseZoneMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWarehouse({ ...row, site_geog_geojson: null });
}

function parseWarehouseZoneResponse(data: unknown, rpcName: string): WarehouseZone {
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseZoneMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWarehouseZone(row);
}

function parseEligibilityResponse(data: unknown, rpcName: string): WarehouseCustomerEligibility {
  const row = firstRow(data);
  if (!row) {
    throw new WarehouseZoneMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWarehouseCustomerEligibility(row);
}

export async function createWarehouse(client: WarehouseZoneMutationRpcClient, input: CreateWarehouseInput): Promise<Warehouse> {
  const parsedInput = CreateWarehouseInputSchema.parse(input);
  const { data, error } = await client.rpc("create_warehouse", {
    p_tenant_id: parsedInput.tenantId,
    p_company_org_unit_id: parsedInput.companyOrgUnitId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_site_address: parsedInput.siteAddress,
    p_timezone: parsedInput.timezone,
    p_site_geojson: parsedInput.siteGeojson,
    p_service_type_eligibility: parsedInput.serviceTypeEligibility,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseWarehouseResponse(data, "create_warehouse");
}

export async function updateWarehouse(client: WarehouseZoneMutationRpcClient, input: UpdateWarehouseInput): Promise<Warehouse> {
  const parsedInput = UpdateWarehouseInputSchema.parse(input);
  const { data, error } = await client.rpc("update_warehouse", {
    p_warehouse_id: parsedInput.warehouseId,
    p_name: parsedInput.name,
    p_site_address: parsedInput.siteAddress,
    p_timezone: parsedInput.timezone,
    p_site_geojson: parsedInput.siteGeojson,
    p_service_type_eligibility: parsedInput.serviceTypeEligibility,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseWarehouseResponse(data, "update_warehouse");
}

export async function setWarehouseStatus(client: WarehouseZoneMutationRpcClient, input: SetWarehouseStatusInput): Promise<Warehouse> {
  const parsedInput = SetWarehouseStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_warehouse_status", {
    p_warehouse_id: parsedInput.warehouseId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseWarehouseResponse(data, "set_warehouse_status");
}

export async function grantWarehouseCustomerEligibility(
  client: WarehouseZoneMutationRpcClient,
  input: GrantWarehouseCustomerEligibilityInput,
): Promise<WarehouseCustomerEligibility> {
  const parsedInput = GrantWarehouseCustomerEligibilityInputSchema.parse(input);
  const { data, error } = await client.rpc("grant_warehouse_customer_eligibility", {
    p_warehouse_id: parsedInput.warehouseId,
    p_customer_account_id: parsedInput.customerAccountId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseEligibilityResponse(data, "grant_warehouse_customer_eligibility");
}

export async function revokeWarehouseCustomerEligibility(
  client: WarehouseZoneMutationRpcClient,
  input: RevokeWarehouseCustomerEligibilityInput,
): Promise<WarehouseCustomerEligibility> {
  const parsedInput = RevokeWarehouseCustomerEligibilityInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_warehouse_customer_eligibility", {
    p_id: parsedInput.id,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseEligibilityResponse(data, "revoke_warehouse_customer_eligibility");
}

export async function createWarehouseZone(client: WarehouseZoneMutationRpcClient, input: CreateWarehouseZoneInput): Promise<WarehouseZone> {
  const parsedInput = CreateWarehouseZoneInputSchema.parse(input);
  const { data, error } = await client.rpc("create_warehouse_zone", {
    p_warehouse_id: parsedInput.warehouseId,
    p_code: parsedInput.code,
    p_name: parsedInput.name,
    p_zone_type: parsedInput.zoneType,
    p_environment: parsedInput.environment,
    p_capacity_value: parsedInput.capacityValue,
    p_capacity_uom: parsedInput.capacityUom,
    p_restrictions: parsedInput.restrictions,
    p_effective_from: parsedInput.effectiveFrom,
    p_effective_to: parsedInput.effectiveTo,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseWarehouseZoneResponse(data, "create_warehouse_zone");
}

export async function updateWarehouseZone(client: WarehouseZoneMutationRpcClient, input: UpdateWarehouseZoneInput): Promise<WarehouseZone> {
  const parsedInput = UpdateWarehouseZoneInputSchema.parse(input);
  const { data, error } = await client.rpc("update_warehouse_zone", {
    p_zone_id: parsedInput.zoneId,
    p_name: parsedInput.name,
    p_environment: parsedInput.environment,
    p_capacity_value: parsedInput.capacityValue,
    p_capacity_uom: parsedInput.capacityUom,
    p_restrictions: parsedInput.restrictions,
    p_effective_from: parsedInput.effectiveFrom,
    p_effective_to: parsedInput.effectiveTo,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseWarehouseZoneResponse(data, "update_warehouse_zone");
}

export async function setWarehouseZoneStatus(client: WarehouseZoneMutationRpcClient, input: SetWarehouseZoneStatusInput): Promise<WarehouseZone> {
  const parsedInput = SetWarehouseZoneStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_warehouse_zone_status", {
    p_zone_id: parsedInput.zoneId,
    p_new_status: parsedInput.newStatus,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WarehouseZoneMutationError(classifyError(error.message), error.message);
  }
  return parseWarehouseZoneResponse(data, "set_warehouse_zone_status");
}
