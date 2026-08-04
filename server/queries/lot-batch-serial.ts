/**
 * Lot, Batch, Serial and Expiry read queries (ATW-016, CG-S10-ATW-016). Thin, typed
 * wrappers around app.get_item_control_policy/app.list_item_control_policy_versions/
 * app.get_lot_identity/app.get_serial_identity/app.list_lot_identities/
 * app.list_serial_identities/app.get_lot_trace/app.get_serial_trace/
 * app.list_allocation_candidates
 * (supabase/migrations/20260730220000_create_advanced_tms_lot_batch_serial_expiry.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseItemControlPolicyVersion,
  parseLotIdentity,
  parseSerialIdentity,
  parseTraceEvent,
  parseAllocationCandidate,
  type ItemControlPolicyVersion,
  type LotIdentity,
  type SerialIdentity,
  type TraceEvent,
  type AllocationCandidate,
  type IdentityStatus,
  type PolicyVersionStatus,
  type AllocationRule,
} from "../contracts/lot-batch-serial/lot-batch-serial.ts";

export type LotBatchSerialQueryClient = Pick<SupabaseClient, "rpc">;

export class LotBatchSerialQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "LotBatchSerialQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** The currently published control policy for an item, or a thrown policy_version_not_found if none has ever been published. */
export async function getItemControlPolicy(client: LotBatchSerialQueryClient, itemMasterId: string, actorAuthUserId: string): Promise<ItemControlPolicyVersion> {
  const { data, error } = await client.rpc("get_item_control_policy", { p_item_master_id: itemMasterId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialQueryError("get_item_control_policy returned no row");
  }
  return parseItemControlPolicyVersion(row);
}

/** Bounded (default 50, hard-capped 200 server-side), optionally narrowed to one item/status. */
export async function listItemControlPolicyVersions(
  client: LotBatchSerialQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { itemMasterId?: string | null; statusFilter?: PolicyVersionStatus | null; limit?: number },
): Promise<ItemControlPolicyVersion[]> {
  const { data, error } = await client.rpc("list_item_control_policy_versions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_item_master_id: options?.itemMasterId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseItemControlPolicyVersion);
}

/** Single-row read by id, RBAC-gated. */
export async function getLotIdentity(client: LotBatchSerialQueryClient, lotIdentityId: string, actorAuthUserId: string): Promise<LotIdentity> {
  const { data, error } = await client.rpc("get_lot_identity", { p_lot_identity_id: lotIdentityId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialQueryError("get_lot_identity returned no row");
  }
  return parseLotIdentity(row);
}

/** Single-row read by id, RBAC-gated. */
export async function getSerialIdentity(client: LotBatchSerialQueryClient, serialIdentityId: string, actorAuthUserId: string): Promise<SerialIdentity> {
  const { data, error } = await client.rpc("get_serial_identity", { p_serial_identity_id: serialIdentityId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new LotBatchSerialQueryError("get_serial_identity returned no row");
  }
  return parseSerialIdentity(row);
}

/** Bounded (default 50, hard-capped 200 server-side), optionally narrowed to one item/owner/status. */
export async function listLotIdentities(
  client: LotBatchSerialQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { itemMasterId?: string | null; ownerAccountId?: string | null; statusFilter?: IdentityStatus | null; limit?: number },
): Promise<LotIdentity[]> {
  const { data, error } = await client.rpc("list_lot_identities", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_item_master_id: options?.itemMasterId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseLotIdentity);
}

/** Bounded (default 50, hard-capped 200 server-side), optionally narrowed to one item/owner/status. */
export async function listSerialIdentities(
  client: LotBatchSerialQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { itemMasterId?: string | null; ownerAccountId?: string | null; statusFilter?: IdentityStatus | null; limit?: number },
): Promise<SerialIdentity[]> {
  const { data, error } = await client.rpc("list_serial_identities", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_item_master_id: options?.itemMasterId ?? null,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_status_filter: options?.statusFilter ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseSerialIdentity);
}

/** Every app.inventory_movement_lines row referencing this lot's own dimension, in chronological order (bounded, default 50, hard-capped 200). */
export async function getLotTrace(client: LotBatchSerialQueryClient, lotIdentityId: string, actorAuthUserId: string, limit?: number): Promise<TraceEvent[]> {
  const { data, error } = await client.rpc("get_lot_trace", { p_lot_identity_id: lotIdentityId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit ?? 50 });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseTraceEvent);
}

/** Every app.inventory_movement_lines row referencing this serial's own dimension, in chronological order (bounded, default 50, hard-capped 200). */
export async function getSerialTrace(client: LotBatchSerialQueryClient, serialIdentityId: string, actorAuthUserId: string, limit?: number): Promise<TraceEvent[]> {
  const { data, error } = await client.rpc("get_serial_trace", { p_serial_identity_id: serialIdentityId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit ?? 50 });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseTraceEvent);
}

/**
 * Real, read-only FIFO/FEFO decision support -- excludes held/quarantined/expired/
 * consumed identities and any lot/serial whose own expiry_date has already passed.
 * Never reserves or consumes stock (app.reserve_inventory/app.consume_inventory_
 * reservation, ATW-015, remain the only real allocation execution path).
 */
export async function listAllocationCandidates(
  client: LotBatchSerialQueryClient,
  tenantId: string,
  warehouseId: string,
  itemMasterId: string,
  actorAuthUserId: string,
  options?: { ownerAccountId?: string | null; allocationRule?: AllocationRule | null; limit?: number },
): Promise<AllocationCandidate[]> {
  const { data, error } = await client.rpc("list_allocation_candidates", {
    p_tenant_id: tenantId,
    p_warehouse_id: warehouseId,
    p_item_master_id: itemMasterId,
    p_owner_account_id: options?.ownerAccountId ?? null,
    p_actor_auth_user_id: actorAuthUserId,
    p_allocation_rule: options?.allocationRule ?? null,
    p_limit: options?.limit ?? 50,
  });
  if (error) {
    throw new LotBatchSerialQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseAllocationCandidate);
}
