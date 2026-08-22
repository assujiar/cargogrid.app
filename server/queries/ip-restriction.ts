/**
 * IP Restriction and Network Access read queries (IAE-028, Prompt 356). Thin,
 * typed wrappers around app.get_or_create_ip_allowlist_policy /
 * app.list_ip_allowlist_entries_for_tenant /
 * app.list_ip_access_evaluations_for_tenant /
 * app.list_ip_allowlist_bypass_grants_for_tenant / app.has_active_ip_allowlist_bypass
 * (supabase/migrations/20260807200000_create_intelligence_ip_restriction_network_access.sql).
 * RPC-only -- every table this capability owns has zero authenticated/anon
 * grant by design (RLS default-deny).
 */

import { parseIpAllowlistPolicy, parseIpAllowlistEntry, parseIpAccessEvaluation, parseIpAllowlistBypassGrant, type IpAllowlistPolicy, type IpAllowlistEntry, type IpAccessEvaluation, type IpAllowlistBypassGrant } from "../contracts/ip-restriction/ip-restriction.ts";

export interface IpRestrictionQueryRpcClient {
  rpc(
    fn:
      | "get_or_create_ip_allowlist_policy"
      | "list_ip_allowlist_entries_for_tenant"
      | "list_ip_access_evaluations_for_tenant"
      | "list_ip_allowlist_bypass_grants_for_tenant"
      | "has_active_ip_allowlist_bypass",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class IpRestrictionQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "IpRestrictionQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** Authority: SEC:View. Idempotent default-row bootstrap. */
export async function getOrCreateIpAllowlistPolicy(client: IpRestrictionQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<IpAllowlistPolicy> {
  const { data, error } = await client.rpc("get_or_create_ip_allowlist_policy", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new IpRestrictionQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new IpRestrictionQueryError("get_or_create_ip_allowlist_policy returned no row");
  }
  return parseIpAllowlistPolicy(data as Record<string, unknown>);
}

/** Authority: SEC:View. */
export async function listIpAllowlistEntries(client: IpRestrictionQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<IpAllowlistEntry[]> {
  const { data, error } = await client.rpc("list_ip_allowlist_entries_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new IpRestrictionQueryError(error.message);
  }
  return asRows(data).map(parseIpAllowlistEntry);
}

/** Authority: SEC:View. Newest first, bounded [1, 200], defaults to 50. */
export async function listIpAccessEvaluations(client: IpRestrictionQueryRpcClient, tenantId: string, actorAuthUserId: string, limit = 50): Promise<IpAccessEvaluation[]> {
  const { data, error } = await client.rpc("list_ip_access_evaluations_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) {
    throw new IpRestrictionQueryError(error.message);
  }
  return asRows(data).map(parseIpAccessEvaluation);
}

/** Authority: SEC:View. */
export async function listIpAllowlistBypassGrants(client: IpRestrictionQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<IpAllowlistBypassGrant[]> {
  const { data, error } = await client.rpc("list_ip_allowlist_bypass_grants_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new IpRestrictionQueryError(error.message);
  }
  return asRows(data).map(parseIpAllowlistBypassGrant);
}

/** service_role-only -- takes no actor/authority parameter of its own by design (see app.assert_ip_allowed's own comment); call with a trusted server-side client that has already resolved tenantId/targetAuthUserId through an authorized path, never with an end-user session client. */
export async function hasActiveIpAllowlistBypass(client: IpRestrictionQueryRpcClient, tenantId: string, targetAuthUserId: string): Promise<boolean> {
  const { data, error } = await client.rpc("has_active_ip_allowlist_bypass", { p_tenant_id: tenantId, p_target_auth_user_id: targetAuthUserId });
  if (error) {
    throw new IpRestrictionQueryError(error.message);
  }
  return data === true;
}
