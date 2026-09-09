/**
 * Rate and Cost Lookup read queries (COM-149, CG-S7-COM-008). Thin, typed wrappers
 * around direct RLS-scoped selects. Reads that need currency/base_amount/minimum_amount/
 * surcharge_components MUST go through app.vendor_rate_versions_directory /
 * app.v_active_vendor_rates (the field-masked projections) -- `authenticated` has no
 * direct column grant on those four columns on app.vendor_rate_versions itself.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseRateVersion,
  parseRateSelection,
  type RateVersion,
  type RateSelection,
} from "../contracts/rate/rate.ts";

export type RateQueryTableClient = Pick<SupabaseClient, "from" | "rpc">;

export class RateQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RateQueryError";
  }
}

/** Every rate version under one master record (any approval_status), most recently created first -- app.vendor_rate_versions_directory is the read path, never the base table directly. */
export async function listRateVersionsForMasterRecord(client: RateQueryTableClient, masterRecordId: string, actorAuthUserId: string): Promise<RateVersion[]> {
  const { data, error } = await client.rpc("list_rate_versions_for_master_record", {
    p_master_record_id: masterRecordId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateVersion(row));
}

/** A single rate version by id (any approval_status) -- returns null (never an error) when RLS/no-match yields zero rows. */
export async function getRateVersionById(client: RateQueryTableClient, rateVersionId: string, actorAuthUserId: string): Promise<RateVersion | null> {
  const { data, error } = await client.rpc("get_rate_version_by_id", {
    p_rate_version_id: rateVersionId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new RateQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseRateVersion(row as Record<string, unknown>);
}

/** Every rate version awaiting approval for one tenant -- for a tenant_admin's own review queue. */
export async function listPendingRateVersions(client: RateQueryTableClient, tenantId: string, actorAuthUserId: string): Promise<RateVersion[]> {
  const { data, error } = await client.rpc("list_pending_rate_versions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateVersion(row));
}

/** Approved, currently-effective rate versions for one tenant -- the same set app.search_vendor_rates queries, useful for a simple unfiltered browse. */
export async function listActiveVendorRates(client: RateQueryTableClient, tenantId: string, actorAuthUserId: string): Promise<RateVersion[]> {
  const { data, error } = await client.rpc("list_active_vendor_rates", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateVersion(row));
}

/** Field-masked rate selections for one costing request, most recently created first -- reads through app.rate_selections_directory, never the base table directly. */
export async function listRateSelectionsForRequest(client: RateQueryTableClient, costingRequestId: string, actorAuthUserId: string): Promise<RateSelection[]> {
  const { data, error } = await client.rpc("list_rate_selections_for_request", {
    p_costing_request_id: costingRequestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateSelection(row));
}
