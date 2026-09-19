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

export interface ListOpportunitiesInput {
  readonly tenantId: string;
  readonly actorAuthUserId: string;
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

/** Server-paginated Opportunity list, via app.list_opportunities (SECURITY DEFINER) -- the real field-masking and can_access_record scope gate. */
export async function listOpportunities(client: OpportunityQueryRpcClient, input: ListOpportunitiesInput): Promise<ListOpportunitiesResult> {
  const pageSize = Math.min(Math.max(Math.trunc(input.pageSize ?? DEFAULT_PAGE_SIZE), 1), MAX_PAGE_SIZE);
  const page = Math.max(Math.trunc(input.page), 1);

  const { data, error } = await client.rpc("list_opportunities", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_page: page,
    p_page_size: pageSize,
  });

  if (error) {
    throw new OpportunityQueryError(error.message);
  }

  const rows = (data ?? []) as Record<string, unknown>[];
  const totalCount = rows.length > 0 ? Number(rows[0]?.total_count) : 0;

  return {
    opportunities: rows.map((row) => parseOpportunity(row)),
    totalCount,
    page,
    pageSize,
  };
}

/** A single opportunity by id (field-masked), for the Opportunity Detail view -- returns null (never an error) when denied/no-match yields zero rows. */
export async function getOpportunityById(client: OpportunityQueryRpcClient, opportunityId: string, actorAuthUserId: string): Promise<Opportunity | null> {
  const { data, error } = await client.rpc("get_opportunity_by_id", {
    p_opportunity_id: opportunityId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new OpportunityQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseOpportunity(row as Record<string, unknown>);
}

/** The stage-transition history for one opportunity, oldest first -- app.list_opportunity_stage_history (SECURITY DEFINER) is the real scope gate. */
export async function listOpportunityStageHistory(client: OpportunityQueryRpcClient, opportunityId: string, actorAuthUserId: string): Promise<OpportunityStageHistoryEntry[]> {
  const { data, error } = await client.rpc("list_opportunity_stage_history", {
    p_opportunity_id: opportunityId,
    p_actor_auth_user_id: actorAuthUserId,
  });
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
