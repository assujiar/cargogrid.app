/**
 * Quotation Builder read queries (COM-151, CG-S7-COM-010). Thin, typed wrappers around
 * direct RLS-scoped selects plus the one read-only RPC (submission readiness). Reads that
 * need sell/cost/margin figures MUST go through app.quotations_directory/
 * app.quotation_lines_directory (the field-masked projections) -- `authenticated` has no
 * direct column grant on those columns on the base tables.
 */

import { BOUNDED_LIST_LIMIT, toBoundedListByCapReached, type BoundedList } from "./bounded-list.ts";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseQuotation,
  parseQuotationLine,
  parseQuotationReadiness,
  type Quotation,
  type QuotationLine,
  type QuotationReadiness,
} from "../contracts/quotation/quotation.ts";

export type QuotationQueryRpcClient = Pick<SupabaseClient, "rpc">;
export type QuotationReadinessRpcClient = Pick<SupabaseClient, "rpc">;

export class QuotationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "QuotationQueryError";
  }
}

/** Field-masked single quotation by id -- app.get_quotation_by_id returns null for both "does not exist" and "exists but RLS denies it," matching every prior Commercial detail query's posture. */
export async function getQuotationById(client: QuotationQueryRpcClient, quotationId: string, actorAuthUserId: string): Promise<Quotation | null> {
  const { data, error } = await client.rpc("get_quotation_by_id", {
    p_quotation_id: quotationId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row) {
    return null;
  }
  return parseQuotation(row as Record<string, unknown>);
}

/** COM-152: every version sharing one root_quotation_id, oldest (version 1) first -- the version history list. */
export async function listQuotationVersions(client: QuotationQueryRpcClient, rootQuotationId: string, actorAuthUserId: string): Promise<Quotation[]> {
  const { data, error } = await client.rpc("list_quotation_versions", {
    p_root_quotation_id: rootQuotationId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
}

/** Field-masked quotations for one opportunity, most recently created first. */
export async function listQuotationsForOpportunity(client: QuotationQueryRpcClient, opportunityId: string, actorAuthUserId: string): Promise<Quotation[]> {
  const { data, error } = await client.rpc("list_quotations_for_opportunity", {
    p_opportunity_id: opportunityId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
}

/** Field-masked quotations for one tenant (any opportunity), most recently created first -- backs the tenant-wide Quotations list page. */
export async function listQuotationsForTenant(client: QuotationQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<BoundedList<Quotation>> {
  const { data, error } = await client.rpc("list_quotations_for_tenant", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: BOUNDED_LIST_LIMIT,
  });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  const rows = (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
  return toBoundedListByCapReached(rows, BOUNDED_LIST_LIMIT);
}

/** Field-masked lines for one quotation, ordered by line_no. */
export async function listQuotationLines(client: QuotationQueryRpcClient, quotationId: string, actorAuthUserId: string): Promise<QuotationLine[]> {
  const { data, error } = await client.rpc("list_quotation_lines", {
    p_quotation_id: quotationId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseQuotationLine(row));
}

/** app.get_quotation_submission_readiness is a read-only RPC (structural pass/fail + reason codes, never a dollar figure) -- called via .rpc() like every other Platform read-only evaluator (app.evaluate_tenant_brand, app.get_opportunity_costing_readiness). */
export async function getQuotationSubmissionReadiness(
  client: QuotationReadinessRpcClient,
  quotationId: string,
  actorAuthUserId: string,
): Promise<QuotationReadiness> {
  const { data, error } = await client.rpc("get_quotation_submission_readiness", {
    p_quotation_id: quotationId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new QuotationQueryError("get_quotation_submission_readiness returned no row");
  }
  return parseQuotationReadiness(row as Record<string, unknown>);
}
