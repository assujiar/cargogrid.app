/**
 * Vendor Profile read queries (PRC-251, CG-S11-PRC-002). Thin, typed wrappers around
 * app.get_vendor_profile/app.list_vendor_profiles/app.list_vendor_contacts/
 * app.list_vendor_addresses/app.list_vendor_services/app.list_vendor_coverage/
 * app.list_vendor_duplicate_candidates/app.search_vendor_duplicate_candidates/
 * app.get_vendor_lifecycle_history
 * (supabase/migrations/20260730580000_create_procurement_vendor_registration.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorProfile,
  parseVendorProfileListRow,
  parseVendorContact,
  parseVendorAddress,
  parseVendorService,
  parseVendorCoverage,
  parseVendorDuplicateCandidate,
  parseVendorDuplicateSearchRow,
  parseVendorLifecycleEvent,
  type VendorProfile,
  type VendorProfileListRow,
  type VendorContact,
  type VendorAddress,
  type VendorService,
  type VendorCoverage,
  type VendorDuplicateCandidate,
  type VendorDuplicateSearchRow,
  type VendorLifecycleEvent,
  type VendorLifecycleStatus,
} from "../contracts/vendor-profile/vendor-profile.ts";

export type VendorProfileQueryClient = Pick<SupabaseClient, "rpc">;

export class VendorProfileQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorProfileQueryError";
  }
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

/** The vendor detail projection (core fields + active child counts). Throws VendorProfileQueryError (translated from vendor_profile_not_found/insufficient_authority) if the caller cannot read it. */
export async function getVendorProfile(client: VendorProfileQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<VendorProfile> {
  const { data, error } = await client.rpc("get_vendor_profile", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  const row = firstRow(data);
  if (!row) {
    throw new VendorProfileQueryError("get_vendor_profile returned no row");
  }
  return parseVendorProfile(row);
}

/** Cursor-paginated directory list, server-filtered/searched -- never a client-loaded full dataset. */
export async function listVendorProfiles(
  client: VendorProfileQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { statusFilter?: VendorLifecycleStatus | null; search?: string | null; limit?: number; afterCode?: string | null },
): Promise<VendorProfileListRow[]> {
  const { data, error } = await client.rpc("list_vendor_profiles", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status_filter: options?.statusFilter ?? null,
    p_search: options?.search ?? null,
    p_limit: options?.limit ?? 50,
    p_after_code: options?.afterCode ?? null,
  });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorProfileListRow);
}

export async function listVendorContacts(client: VendorProfileQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<VendorContact[]> {
  const { data, error } = await client.rpc("list_vendor_contacts", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorContact);
}

export async function listVendorAddresses(client: VendorProfileQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<VendorAddress[]> {
  const { data, error } = await client.rpc("list_vendor_addresses", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorAddress);
}

export async function listVendorServices(client: VendorProfileQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<VendorService[]> {
  const { data, error } = await client.rpc("list_vendor_services", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorService);
}

export async function listVendorCoverage(client: VendorProfileQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<VendorCoverage[]> {
  const { data, error } = await client.rpc("list_vendor_coverage", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorCoverage);
}

export async function listVendorDuplicateCandidates(client: VendorProfileQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<VendorDuplicateCandidate[]> {
  const { data, error } = await client.rpc("list_vendor_duplicate_candidates", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorDuplicateCandidate);
}

/** Trigram-based fuzzy match over existing vendor_profiles.legal_name/trade_name -- the duplicate-review screen's own candidate suggestion source, distinct from the persisted app.vendor_duplicate_candidates rows listVendorDuplicateCandidates reads. */
export async function searchVendorDuplicateCandidates(
  client: VendorProfileQueryClient,
  tenantId: string,
  legalName: string,
  tradeName: string | null,
  actorAuthUserId: string,
  limit = 10,
): Promise<VendorDuplicateSearchRow[]> {
  const { data, error } = await client.rpc("search_vendor_duplicate_candidates", {
    p_tenant_id: tenantId,
    p_legal_name: legalName,
    p_trade_name: tradeName,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit,
  });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorDuplicateSearchRow);
}

export async function getVendorLifecycleHistory(client: VendorProfileQueryClient, masterRecordId: string, actorAuthUserId: string): Promise<VendorLifecycleEvent[]> {
  const { data, error } = await client.rpc("get_vendor_lifecycle_history", { p_master_record_id: masterRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorProfileQueryError(error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorLifecycleEvent);
}
