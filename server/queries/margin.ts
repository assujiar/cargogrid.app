/**
 * Margin Calculation read queries (COM-150, CG-S7-COM-009). Thin, typed wrappers around
 * direct RLS-scoped selects. Reads that need cost/margin/markup/sell/discount MUST go
 * through app.margin_calculations_directory (the field-masked projection) -- `authenticated`
 * has no direct column grant on those columns on app.margin_calculations itself.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseMarginRuleVersion,
  parseMarginCalculation,
  type MarginRuleVersion,
  type MarginCalculation,
} from "../contracts/margin/margin.ts";

export type MarginQueryTableClient = Pick<SupabaseClient, "from">;

export class MarginQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MarginQueryError";
  }
}

/** The tenant's currently published margin rule, if any -- returns null (never an error) when none exists. */
export async function getPublishedMarginRule(client: MarginQueryTableClient, tenantId: string): Promise<MarginRuleVersion | null> {
  const { data, error } = await client.from("margin_rule_versions").select("*").eq("tenant_id", tenantId).eq("status", "published").maybeSingle();
  if (error) {
    throw new MarginQueryError(error.message);
  }
  if (!data) {
    return null;
  }
  return parseMarginRuleVersion(data as Record<string, unknown>);
}

/** Every margin rule version for one tenant (any status), most recently created first. */
export async function listMarginRuleVersions(client: MarginQueryTableClient, tenantId: string): Promise<MarginRuleVersion[]> {
  const { data, error } = await client.from("margin_rule_versions").select("*").eq("tenant_id", tenantId).order("created_at", { ascending: false });
  if (error) {
    throw new MarginQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseMarginRuleVersion(row));
}

/** Field-masked margin calculations for one costing request, most recently created first -- reads through app.margin_calculations_directory, never the base table directly. */
export async function listMarginCalculationsForRequest(client: MarginQueryTableClient, costingRequestId: string): Promise<MarginCalculation[]> {
  const { data, error } = await client
    .from("margin_calculations_directory")
    .select("*")
    .eq("costing_request_id", costingRequestId)
    .order("created_at", { ascending: false });
  if (error) {
    throw new MarginQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseMarginCalculation(row));
}
