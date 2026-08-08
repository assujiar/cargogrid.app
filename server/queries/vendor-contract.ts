/**
 * Vendor Contract read queries (PRC-261, CG-S11-PRC-012). Thin, typed wrappers around
 * the dedicated read RPCs (supabase/migrations/20260730700000_create_procurement_
 * vendor_contract.sql) -- mirrors server/queries/purchase-order.ts exactly: every RPC
 * already carries its own explicit evaluate_permission check plus PRC:View cost field
 * masking, so this file calls `.rpc(...)`, never `.from(...)`, on a base table.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseVendorContract, parseVendorContractEvent, type VendorContract, type VendorContractEvent, type VendorContractStatus } from "../contracts/vendor-contract/vendor-contract.ts";

export type VendorContractQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorContractQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorContractQueryError";
  }
}

const VENDOR_CONTRACT_LIST_DEFAULT_LIMIT = 25;

/** A single vendor contract version. Throws on a real error; the RPC itself raises vendor_contract_not_found/insufficient_authority as thrown errors, never a null return. */
export async function getVendorContract(client: VendorContractQueryRpcClient, contractId: string, actorAuthUserId: string): Promise<VendorContract> {
  const { data, error } = await client.rpc("get_vendor_contract", { p_contract_id: contractId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorContractQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorContractQueryError("get_vendor_contract returned no row");
  }
  return parseVendorContract(row as Record<string, unknown>);
}

/** Tenant-scoped contract queue, optionally filtered by vendor and/or status. Server-side clamped to <=100 rows. */
export async function listVendorContracts(
  client: VendorContractQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  vendorMasterId: string | null = null,
  statusFilter: VendorContractStatus | null = null,
  limit: number = VENDOR_CONTRACT_LIST_DEFAULT_LIMIT,
): Promise<VendorContract[]> {
  const { data, error } = await client.rpc("list_vendor_contracts", {
    p_tenant_id: tenantId,
    p_vendor_master_id: vendorMasterId,
    p_status: statusFilter,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit,
    p_cursor: null,
  });
  if (error) {
    throw new VendorContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorContract(row));
}

/** Every version of a logical contract (same contract_number), ordered by version_no -- the version-diff/history surface (Prompt 261 §15). */
export async function listVendorContractVersions(client: VendorContractQueryRpcClient, contractNumber: string, tenantId: string, actorAuthUserId: string): Promise<VendorContract[]> {
  const { data, error } = await client.rpc("list_vendor_contract_versions", { p_contract_number: contractNumber, p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorContract(row));
}

/** The full lifecycle timeline for one contract version, in occurrence order. */
export async function getVendorContractLifecycleHistory(client: VendorContractQueryRpcClient, contractId: string, actorAuthUserId: string): Promise<VendorContractEvent[]> {
  const { data, error } = await client.rpc("get_vendor_contract_lifecycle_history", { p_contract_id: contractId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorContractEvent(row));
}

/** The deterministic single-active-row effective-term resolution point downstream capabilities (PRC-263/264/265) read from. Returns null (never throws not-found) when no contract is effective. */
export async function resolveEffectiveVendorContract(
  client: VendorContractQueryRpcClient,
  tenantId: string,
  vendorMasterId: string,
  asOf: string | null,
  actorAuthUserId: string,
): Promise<VendorContract | null> {
  const { data, error } = await client.rpc("resolve_effective_vendor_contract", { p_tenant_id: tenantId, p_vendor_master_id: vendorMasterId, p_as_of: asOf, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorContractQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object" || row.id == null) {
    return null;
  }
  return parseVendorContract(row as Record<string, unknown>);
}

/** Active contracts whose effective_end falls within the given window -- the read-only expiry-reminder surface (design note 7 of the migration: no async job exists to dispatch from yet). */
export async function listVendorContractsExpiring(client: VendorContractQueryRpcClient, tenantId: string, withinDays: number, actorAuthUserId: string): Promise<VendorContract[]> {
  const { data, error } = await client.rpc("list_vendor_contracts_expiring", { p_tenant_id: tenantId, p_within_days: withinDays, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorContractQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorContract(row));
}
