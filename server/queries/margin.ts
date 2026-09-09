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

export type MarginQueryTableClient = Pick<SupabaseClient, "rpc">;

export class MarginQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MarginQueryError";
  }
}

/** The tenant's currently published margin rule, if any -- returns null (never an error) when none exists. */
export async function getPublishedMarginRule(client: MarginQueryTableClient, tenantId: string, actorAuthUserId: string): Promise<MarginRuleVersion | null> {
  const { data, error } = await client.rpc("get_published_margin_rule", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new MarginQueryError(error.message);
  }
  const row = Array.isArray(data) ? (data[0] ?? null) : data;
  if (!row) {
    return null;
  }
  return parseMarginRuleVersion(row as Record<string, unknown>);
}

/** Every margin rule version for one tenant (any status), most recently created first. */
export async function listMarginRuleVersions(client: MarginQueryTableClient, tenantId: string, actorAuthUserId: string): Promise<MarginRuleVersion[]> {
  const { data, error } = await client.rpc("list_margin_rule_versions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_limit: 200,
  });
  if (error) {
    throw new MarginQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseMarginRuleVersion(row));
}

/** Field-masked margin calculations for one costing request, most recently created first -- app.list_margin_calculations_for_request (SECURITY DEFINER) is the real scope/masking gate. */
export async function listMarginCalculationsForRequest(client: MarginQueryTableClient, costingRequestId: string, actorAuthUserId: string): Promise<MarginCalculation[]> {
  const { data, error } = await client.rpc("list_margin_calculations_for_request", {
    p_costing_request_id: costingRequestId,
    p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) {
    throw new MarginQueryError(error.message);
  }
  return (data ?? []).map((row: Record<string, unknown>) => parseMarginCalculation(row));
}
