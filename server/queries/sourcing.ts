/**
 * Sourcing read queries (PRC-256, CG-S11-PRC-007). Thin, typed wrappers around
 * the four dedicated read RPCs
 * (supabase/migrations/20260730630000_create_procurement_sourcing.sql) --
 * unlike PRC-255's own server/queries/procurement-rate.ts (which reads
 * directly from a masked/plain _directory view via `.from(...)`), PRC-256's
 * own spec defines dedicated read RPCs for every list/get here, each with its
 * own explicit evaluate_permission check and (for the cost-sensitive
 * sourcing-request shape) actor-parameterized masking -- so this file calls
 * `.rpc(...)`, never `.from(...)`, on a base table or a view. The RPCs
 * themselves are the ones that never select from a base table without going
 * through their own masked projection (mirroring app.search_vendor_rates'
 * PRC-255 precedent) -- this file is a thin pass-through on top of that.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseSourcingRequest,
  parseSourcingCandidate,
  parseSourcingRequestEvent,
  type SourcingRequest,
  type SourcingCandidate,
  type SourcingRequestEvent,
} from "../contracts/sourcing/sourcing.ts";

export type SourcingQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class SourcingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SourcingQueryError";
  }
}

// app.list_sourcing_requests itself clamps server-side to <=200 rows regardless
// of what is requested (PRC-255's own disclosed .limit(200) precedent) -- this
// client-side default only picks a reasonable per-request page size.
const SOURCING_REQUEST_LIST_DEFAULT_LIMIT = 50;

/** A single sourcing request, budget_amount masked behind PRC:View cost. Throws on a real error; the RPC itself raises sourcing_request_not_found/insufficient_privilege as thrown errors, never a null return. */
export async function getSourcingRequest(client: SourcingQueryRpcClient, sourcingRequestId: string, actorAuthUserId: string): Promise<SourcingRequest> {
  const { data, error } = await client.rpc("get_sourcing_request", {
    p_sourcing_request_id: sourcingRequestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new SourcingQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new SourcingQueryError("get_sourcing_request returned no row");
  }
  return parseSourcingRequest(data as Record<string, unknown>);
}

/** Tenant-scoped sourcing request queue, optionally filtered by status. Server-side clamped to <=200 rows (app.list_sourcing_requests' own bound). */
export async function listSourcingRequests(
  client: SourcingQueryRpcClient,
  tenantId: string,
  actorAuthUserId: string,
  status: string | null = null,
  limit: number = SOURCING_REQUEST_LIST_DEFAULT_LIMIT,
): Promise<SourcingRequest[]> {
  const { data, error } = await client.rpc("list_sourcing_requests", {
    p_tenant_id: tenantId,
    p_status: status,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: limit,
  });
  if (error) {
    throw new SourcingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSourcingRequest(row));
}

/** Every candidate longlist row for one sourcing request, most-eligible first. */
export async function listSourcingCandidates(client: SourcingQueryRpcClient, sourcingRequestId: string, actorAuthUserId: string): Promise<SourcingCandidate[]> {
  const { data, error } = await client.rpc("list_sourcing_candidates", {
    p_sourcing_request_id: sourcingRequestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new SourcingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSourcingCandidate(row));
}

/** The full lifecycle timeline for one sourcing request, in occurrence order. */
export async function getSourcingRequestHistory(client: SourcingQueryRpcClient, sourcingRequestId: string, actorAuthUserId: string): Promise<SourcingRequestEvent[]> {
  const { data, error } = await client.rpc("get_sourcing_request_history", {
    p_sourcing_request_id: sourcingRequestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new SourcingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseSourcingRequestEvent(row));
}
