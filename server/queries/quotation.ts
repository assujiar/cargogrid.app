/**
 * Quotation Builder read queries (COM-151, CG-S7-COM-010). Thin, typed wrappers around
 * direct RLS-scoped selects plus the one read-only RPC (submission readiness). Reads that
 * need sell/cost/margin figures MUST go through app.quotations_directory/
 * app.quotation_lines_directory (the field-masked projections) -- `authenticated` has no
 * direct column grant on those columns on the base tables.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseQuotation,
  parseQuotationLine,
  parseQuotationReadiness,
  type Quotation,
  type QuotationLine,
  type QuotationReadiness,
} from "../contracts/quotation/quotation.ts";

export type QuotationQueryTableClient = Pick<SupabaseClient, "from">;
export type QuotationReadinessRpcClient = Pick<SupabaseClient, "rpc">;

export class QuotationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "QuotationQueryError";
  }
}

/** Field-masked single quotation by id -- returns null for both "does not exist" and "exists but RLS denies it," matching every prior Commercial detail query's posture. */
export async function getQuotationById(client: QuotationQueryTableClient, quotationId: string): Promise<Quotation | null> {
  const { data, error } = await client.from("quotations_directory").select("*").eq("id", quotationId).maybeSingle();
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseQuotation(data as Record<string, unknown>);
}

/** Field-masked quotations for one opportunity, most recently created first. */
export async function listQuotationsForOpportunity(client: QuotationQueryTableClient, opportunityId: string): Promise<Quotation[]> {
  const { data, error } = await client
    .from("quotations_directory")
    .select("*")
    .eq("opportunity_id", opportunityId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
}

/** Field-masked quotations for one tenant (any opportunity), most recently created first -- backs the tenant-wide Quotations list page. */
export async function listQuotationsForTenant(client: QuotationQueryTableClient, tenantId: string): Promise<Quotation[]> {
  const { data, error } = await client
    .from("quotations_directory")
    .select("*")
    .eq("tenant_id", tenantId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new QuotationQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseQuotation(row));
}

/** Field-masked lines for one quotation, ordered by line_no. */
export async function listQuotationLines(client: QuotationQueryTableClient, quotationId: string): Promise<QuotationLine[]> {
  const { data, error } = await client
    .from("quotation_lines_directory")
    .select("*")
    .eq("quotation_id", quotationId)
    .order("line_no", { ascending: true });
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
