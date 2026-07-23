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

export type CostingQueryTableClient = Pick<SupabaseClient, "from">;

export class CostingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CostingQueryError";
  }
}

/** All costing requests for one opportunity, most recently created first -- RLS (costing_requests_select_scoped) is the real scope gate. */
export async function listCostingRequestsForOpportunity(client: CostingQueryTableClient, opportunityId: string): Promise<CostingRequest[]> {
  const { data, error } = await client
    .from("costing_requests")
    .select("*")
    .eq("opportunity_id", opportunityId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingRequest(row));
}

/** A single costing request by id -- returns null (never an error) when RLS/no-match yields zero rows. */
export async function getCostingRequestById(client: CostingQueryTableClient, requestId: string): Promise<CostingRequest | null> {
  const { data, error } = await client.from("costing_requests").select("*").eq("id", requestId).maybeSingle();
  if (error) {
    throw new CostingQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseCostingRequest(data as Record<string, unknown>);
}

/** The requested line items for one costing request -- RLS (costing_request_components_select_scoped) is the real scope gate. */
export async function listCostingRequestComponents(client: CostingQueryTableClient, requestId: string): Promise<CostingRequestComponent[]> {
  const { data, error } = await client
    .from("costing_request_components")
    .select("*")
    .eq("costing_request_id", requestId)
    .order("created_at", { ascending: true });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingRequestComponent(row));
}

/** Field-masked responses for one costing request, most recently created first -- reads through app.costing_responses_directory, never the base table directly. */
export async function listCostingResponsesForRequest(client: CostingQueryTableClient, requestId: string): Promise<CostingResponse[]> {
  const { data, error } = await client
    .from("costing_responses_directory")
    .select("*")
    .eq("costing_request_id", requestId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingResponse(row));
}

/** Priced line items for one response -- zero rows (not an error) for a caller lacking COM:View cost (costing_response_components_select_scoped denies entirely, no masked-but-visible state). */
export async function listCostingResponseComponents(client: CostingQueryTableClient, responseId: string): Promise<CostingResponseComponent[]> {
  const { data, error } = await client
    .from("costing_response_components")
    .select("*")
    .eq("costing_response_id", responseId)
    .order("created_at", { ascending: true });
  if (error) {
    throw new CostingQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseCostingResponseComponent(row));
}
