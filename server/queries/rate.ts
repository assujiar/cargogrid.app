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

export type RateQueryTableClient = Pick<SupabaseClient, "from">;

export class RateQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RateQueryError";
  }
}

/** Every rate version under one master record (any approval_status), most recently created first -- app.vendor_rate_versions_directory is the read path, never the base table directly. */
export async function listRateVersionsForMasterRecord(client: RateQueryTableClient, masterRecordId: string): Promise<RateVersion[]> {
  const { data, error } = await client
    .from("vendor_rate_versions_directory")
    .select("*")
    .eq("master_record_id", masterRecordId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateVersion(row));
}

/** A single rate version by id (any approval_status) -- returns null (never an error) when RLS/no-match yields zero rows. */
export async function getRateVersionById(client: RateQueryTableClient, rateVersionId: string): Promise<RateVersion | null> {
  const { data, error } = await client.from("vendor_rate_versions_directory").select("*").eq("rate_version_id", rateVersionId).maybeSingle();
  if (error) {
    throw new RateQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseRateVersion(data as Record<string, unknown>);
}

/** Every rate version awaiting approval for one tenant -- for a tenant_admin's own review queue. */
export async function listPendingRateVersions(client: RateQueryTableClient, tenantId: string): Promise<RateVersion[]> {
  const { data, error } = await client
    .from("vendor_rate_versions_directory")
    .select("*")
    .eq("tenant_id", tenantId)
    .eq("approval_status", "pending_approval")
    .order("created_at", { ascending: false });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateVersion(row));
}

/** Approved, currently-effective rate versions for one tenant -- the same set app.search_vendor_rates queries, useful for a simple unfiltered browse. */
export async function listActiveVendorRates(client: RateQueryTableClient, tenantId: string): Promise<RateVersion[]> {
  const { data, error } = await client
    .from("v_active_vendor_rates")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("vendor_code", { ascending: true });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateVersion(row));
}

/** Field-masked rate selections for one costing request, most recently created first -- reads through app.rate_selections_directory, never the base table directly. */
export async function listRateSelectionsForRequest(client: RateQueryTableClient, costingRequestId: string): Promise<RateSelection[]> {
  const { data, error } = await client
    .from("rate_selections_directory")
    .select("*")
    .eq("costing_request_id", costingRequestId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new RateQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseRateSelection(row));
}
