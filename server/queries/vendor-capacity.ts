/**
 * Vendor Capacity and Availability read queries (PRC-262, CG-S11-PRC-013). Thin,
 * typed wrappers around the dedicated read RPCs (supabase/migrations/
 * 20260730710000_create_procurement_vendor_capacity.sql) -- mirrors
 * server/queries/vendor-contract.ts exactly: every RPC already carries its own
 * explicit evaluate_permission check, so this file calls `.rpc(...)`, never
 * `.from(...)`, on a base table.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorCapacityOffer,
  parseVendorCapacityBlackout,
  parseVendorCapacityReservation,
  type VendorCapacityOffer,
  type VendorCapacityBlackout,
  type VendorCapacityReservation,
  type VendorCapacityOfferStatus,
} from "../contracts/vendor-capacity/vendor-capacity.ts";

export type VendorCapacityQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorCapacityQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorCapacityQueryError";
  }
}

export async function getVendorCapacityOffer(client: VendorCapacityQueryRpcClient, offerId: string, actorAuthUserId: string): Promise<VendorCapacityOffer> {
  const { data, error } = await client.rpc("get_vendor_capacity_offer", { p_offer_id: offerId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorCapacityQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorCapacityQueryError("get_vendor_capacity_offer returned no row");
  }
  return parseVendorCapacityOffer(row as Record<string, unknown>);
}

export async function listVendorCapacityOffers(
  client: VendorCapacityQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  vendorMasterId: string | null = null,
  statusFilter: VendorCapacityOfferStatus | null = null,
  serviceType: string | null = null,
  limit = 25,
): Promise<VendorCapacityOffer[]> {
  const { data, error } = await client.rpc("list_vendor_capacity_offers", {
    p_tenant_id: tenantId,
    p_vendor_master_id: vendorMasterId,
    p_status: statusFilter,
    p_service_type: serviceType,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit,
  });
  if (error) {
    throw new VendorCapacityQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorCapacityOffer(row));
}

export async function listVendorCapacityBlackouts(client: VendorCapacityQueryRpcClient, offerId: string, actorAuthUserId: string): Promise<VendorCapacityBlackout[]> {
  const { data, error } = await client.rpc("list_vendor_capacity_blackouts", { p_offer_id: offerId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorCapacityQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorCapacityBlackout(row));
}

export async function listVendorCapacityReservations(
  client: VendorCapacityQueryRpcClient,
  offerId: string,
  actorAuthUserId: string,
  statusFilter: string | null = null,
): Promise<VendorCapacityReservation[]> {
  const { data, error } = await client.rpc("list_vendor_capacity_reservations", { p_offer_id: offerId, p_status: statusFilter, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorCapacityQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorCapacityReservation(row));
}

export async function getVendorCapacityReservation(client: VendorCapacityQueryRpcClient, reservationId: string, actorAuthUserId: string): Promise<VendorCapacityReservation> {
  const { data, error } = await client.rpc("get_vendor_capacity_reservation", { p_reservation_id: reservationId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorCapacityQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorCapacityQueryError("get_vendor_capacity_reservation returned no row");
  }
  return parseVendorCapacityReservation(row as Record<string, unknown>);
}

/** Advisory-only preview (no lock) -- the real, race-safe enforcement is app.reserve_vendor_capacity's own locked computation (migration design note 2). */
export async function computeVendorCapacityAvailable(
  client: VendorCapacityQueryRpcClient,
  offerId: string,
  windowStart: string,
  windowEnd: string,
  actorAuthUserId: string,
): Promise<number> {
  const { data, error } = await client.rpc("compute_vendor_capacity_available", { p_offer_id: offerId, p_window_start: windowStart, p_window_end: windowEnd, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorCapacityQueryError(error.message);
  }
  return Number(data);
}
