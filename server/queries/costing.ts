/**
 * RFQ and Costing Request read queries (COM-148, CG-S7-COM-007). Thin, typed wrappers
 * around direct RLS-scoped selects. Reads that need currency/total_amount MUST go through
 * app.costing_responses_directory (the field-masked projection) -- `authenticated` has no
 * direct column grant on those two columns on app.costing_responses itself.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseCostingRequest,
  parseCostingRequestComponent,
  parseCostingResponse,
  parseCostingResponseComponent,
  type CostingRequest,
  type CostingRequestComponent,
  type CostingResponse,
  type CostingResponseComponent,
} from "../contracts/costing/costing.ts";

export type CostingQueryTableClient = Pick<SupabaseClient, "rpc">;

export class CostingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CostingQueryError";
  }
}

/** All costing requests for one opportunity, most recently created first -- app.list_costing_requests_for_opportunity (SECURITY DEFINER) is the real scope gate. */
export async function listCostingRequestsForOpportunity(client: CostingQueryTableClient, opportunityId: string, actorAuthUserId: string): Promise<CostingRequest[]> {
  const { data, error } = await client.rpc("list_costing_requests_for_opportunity", {
    p_opportunity_id: opportunityId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingRequest(row));
}

/** A single costing request by id -- returns null (never an error) when denied/no-match yields zero rows. */
export async function getCostingRequestById(client: CostingQueryTableClient, requestId: string, actorAuthUserId: string): Promise<CostingRequest | null> {
  const { data, error } = await client.rpc("get_costing_request_by_id", {
    p_request_id: requestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  const row = (data ?? [])[0];
  if (!row) {
    return null;
  }
  return parseCostingRequest(row as Record<string, unknown>);
}

/** The requested line items for one costing request -- app.list_costing_request_components (SECURITY DEFINER) is the real scope gate. */
export async function listCostingRequestComponents(client: CostingQueryTableClient, requestId: string, actorAuthUserId: string): Promise<CostingRequestComponent[]> {
  const { data, error } = await client.rpc("list_costing_request_components", {
    p_request_id: requestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingRequestComponent(row));
}

/** Field-masked responses for one costing request, most recently created first -- app.list_costing_responses_for_request (SECURITY DEFINER) is the real scope/masking gate. */
export async function listCostingResponsesForRequest(client: CostingQueryTableClient, requestId: string, actorAuthUserId: string): Promise<CostingResponse[]> {
  const { data, error } = await client.rpc("list_costing_responses_for_request", {
    p_request_id: requestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingResponse(row));
}

/** Priced line items for one response -- zero rows (not an error) for a caller lacking COM:View cost (app.list_costing_response_components denies entirely, no masked-but-visible state). */
export async function listCostingResponseComponents(client: CostingQueryTableClient, responseId: string, actorAuthUserId: string): Promise<CostingResponseComponent[]> {
  const { data, error } = await client.rpc("list_costing_response_components", {
    p_response_id: responseId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingResponseComponent(row));
}
