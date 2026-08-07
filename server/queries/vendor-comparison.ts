/**
 * Vendor Comparison read queries (PRC-258, CG-S11-PRC-009). Thin, typed
 * wrappers around the dedicated read RPCs (supabase/migrations/
 * 20260730650000_create_procurement_vendor_comparison.sql) -- mirrors
 * server/queries/rfq.ts exactly: every RPC already carries its own explicit
 * evaluate_permission check (PRC:View cost alone, migration design note 8),
 * so this file calls `.rpc(...)`, never `.from(...)`, on a base table or a
 * view.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseVendorComparison,
  parseVendorComparisonOffer,
  parseVendorComparisonOfferScore,
  parseVendorComparisonEvent,
  type VendorComparison,
  type VendorComparisonOffer,
  type VendorComparisonOfferScore,
  type VendorComparisonEvent,
} from "../contracts/vendor-comparison/vendor-comparison.ts";

export type VendorComparisonQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class VendorComparisonQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "VendorComparisonQueryError";
  }
}

// app.list_vendor_comparisons itself clamps server-side to <=200 rows
// regardless of what is requested (PRC-256/PRC-257's own disclosed
// .limit(200) precedent) -- this client-side default only picks a
// reasonable per-request page size.
const VENDOR_COMPARISON_LIST_DEFAULT_LIMIT = 50;

/** A single vendor comparison. Throws on a real error; the RPC itself raises vendor_comparison_not_found/insufficient_privilege as thrown errors, never a null return. */
export async function getVendorComparison(client: VendorComparisonQueryRpcClient, comparisonId: string, actorAuthUserId: string): Promise<VendorComparison> {
  const { data, error } = await client.rpc("get_vendor_comparison", { p_comparison_id: comparisonId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorComparisonQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new VendorComparisonQueryError("get_vendor_comparison returned no row");
  }
  return parseVendorComparison(data as Record<string, unknown>);
}

/** Tenant-scoped comparison queue, optionally filtered by rfqId and/or status. With no status filter, superseded (historical) versions are excluded by default. Server-side clamped to <=200 rows. */
export async function listVendorComparisons(
  client: VendorComparisonQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  rfqId: string | null = null,
  status: string | null = null,
  limit: number = VENDOR_COMPARISON_LIST_DEFAULT_LIMIT,
): Promise<VendorComparison[]> {
  const { data, error } = await client.rpc("list_vendor_comparisons", {
    p_tenant_id: tenantId,
    p_rfq_id: rfqId,
    p_status: status,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit,
  });
  if (error) {
    throw new VendorComparisonQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorComparison(row));
}

/** Every normalized offer for one comparison, ordered by rank (unranked/excluded last). */
export async function listVendorComparisonOffers(client: VendorComparisonQueryRpcClient, comparisonId: string, actorAuthUserId: string): Promise<VendorComparisonOffer[]> {
  const { data, error } = await client.rpc("list_vendor_comparison_offers", { p_comparison_id: comparisonId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorComparisonQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorComparisonOffer(row));
}

/** Every non-price criterion score for one offer. */
export async function listVendorComparisonOfferScores(client: VendorComparisonQueryRpcClient, comparisonOfferId: string, actorAuthUserId: string): Promise<VendorComparisonOfferScore[]> {
  const { data, error } = await client.rpc("list_vendor_comparison_offer_scores", { p_comparison_offer_id: comparisonOfferId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorComparisonQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorComparisonOfferScore(row));
}

/** The full lifecycle timeline (comparison-root transitions only) for one comparison, in occurrence order. */
export async function getVendorComparisonHistory(client: VendorComparisonQueryRpcClient, comparisonId: string, actorAuthUserId: string): Promise<VendorComparisonEvent[]> {
  const { data, error } = await client.rpc("get_vendor_comparison_history", { p_comparison_id: comparisonId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new VendorComparisonQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseVendorComparisonEvent(row));
}
