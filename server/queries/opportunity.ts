/**
 * Opportunity Management read queries (COM-147, CG-S7-COM-006). Thin, typed wrappers
 * around app.get_opportunity_costing_readiness and direct RLS-scoped selects. Reads that
 * need value_amount/value_currency/probability MUST go through app.opportunities_directory
 * (the field-masked projection) -- `authenticated` has no direct column grant on those
 * three columns on app.opportunities itself, so a plain select against the base table
 * silently omits them rather than erroring, per Postgres's normal column-privilege
 * behavior for an explicit column list (`select *` still succeeds, just without those
 * columns present).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseOpportunity, parseOpportunityStageHistoryEntry, parseCostingReadiness, type Opportunity, type OpportunityStageHistoryEntry, type CostingReadiness } from "../contracts/opportunity/opportunity.ts";

const MAX_PAGE_SIZE = 100;
const DEFAULT_PAGE_SIZE = 50;

export type OpportunityQueryRpcClient = Pick<SupabaseClient, "rpc">;
export type OpportunityQueryTableClient = Pick<SupabaseClient, "from">;

export interface ListOpportunitiesInput {
  readonly tenantId: string;
  readonly page: number;
  readonly pageSize?: number;
}

export interface ListOpportunitiesResult {
  readonly opportunities: readonly Opportunity[];
  readonly totalCount: number;
  readonly page: number;
  readonly pageSize: number;
}

export class OpportunityQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OpportunityQueryError";
  }
}

/** Server-paginated Opportunity list, via the field-masked directory view -- RLS plus the view's own can_access_record filter is the real scope gate. */
export async function listOpportunities(client: OpportunityQueryTableClient, input: ListOpportunitiesInput): Promise<ListOpportunitiesResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const { data, error, count } = await client
    .from("opportunities_directory")
    .select("*", { count: "exact" })
    .eq("tenant_id", input.tenantId)
    .order("created_at", { ascending: false })
    .range(from, to);

  if (error) {
    throw new OpportunityQueryError(error.message);
  }

  return {
    opportunities: (data ?? []).map((row: Record<string, unknown>) => parseOpportunity(row)),
    totalCount: count ?? 0,
    page,
    pageSize,
  };
}

/** A single opportunity by id (field-masked), for the Opportunity Detail view -- returns null (never an error) when RLS/no-match yields zero rows. */
export async function getOpportunityById(client: OpportunityQueryTableClient, opportunityId: string): Promise<Opportunity | null> {
  const { data, error } = await client.from("opportunities_directory").select("*").eq("id", opportunityId).maybeSingle();
  if (error) {
    throw new OpportunityQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseOpportunity(data as Record<string, unknown>);
}

/** The stage-transition history for one opportunity, oldest first -- RLS (opportunity_stage_history_select_scoped) is the real scope gate. */
export async function listOpportunityStageHistory(client: OpportunityQueryTableClient, opportunityId: string): Promise<OpportunityStageHistoryEntry[]> {
  const { data, error } = await client
    .from("opportunity_stage_history")
    .select("*")
    .eq("opportunity_id", opportunityId)
    .order("changed_at", { ascending: true });
  if (error) {
    throw new OpportunityQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseOpportunityStageHistoryEntry(row));
}

/** Fixed, deterministic data-completeness check over the requirements snapshot -- not the deferred Configuration Engine rule evaluator. */
export async function getOpportunityCostingReadiness(client: OpportunityQueryRpcClient, opportunityId: string, actorAuthUserId: string): Promise<CostingReadiness> {
  const { data, error } = await client.rpc("get_opportunity_costing_readiness", {
    p_opportunity_id: opportunityId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new OpportunityQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new OpportunityQueryError("get_opportunity_costing_readiness returned no row");
  }
  return parseCostingReadiness(row as Record<string, unknown>);
}
