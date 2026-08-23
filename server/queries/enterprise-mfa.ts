/**
 * Enterprise MFA and Session Controls read queries (IAE-027, Prompt 355).
 * Thin, typed wrappers around app.get_or_create_mfa_tenant_policy /
 * app.list_user_sessions_for_tenant / app.list_mfa_exceptions_for_tenant /
 * app.list_mfa_step_up_challenges_for_tenant
 * (supabase/migrations/20260807100000_create_intelligence_enterprise_mfa_session_controls.sql).
 * RPC-only, not a direct table `.from()` read -- every table this capability
 * owns has zero authenticated/anon grant by design (RLS default-deny).
 */

import { parseMfaTenantPolicy, parseUserSession, parseMfaException, parseMfaStepUpChallenge, type MfaTenantPolicy, type UserSession, type MfaException, type MfaStepUpChallenge } from "../contracts/enterprise-mfa/enterprise-mfa.ts";

export interface EnterpriseMfaQueryRpcClient {
  rpc(
    fn: "get_or_create_mfa_tenant_policy" | "list_user_sessions_for_tenant" | "list_mfa_exceptions_for_tenant" | "list_mfa_step_up_challenges_for_tenant",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class EnterpriseMfaQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EnterpriseMfaQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** Authority: SEC:View. Idempotent default-row bootstrap -- a tenant with no explicit policy yet still gets real, sensible defaults. */
export async function getOrCreateMfaTenantPolicy(client: EnterpriseMfaQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<MfaTenantPolicy> {
  const { data, error } = await client.rpc("get_or_create_mfa_tenant_policy", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseMfaQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new EnterpriseMfaQueryError("get_or_create_mfa_tenant_policy returned no row");
  }
  return parseMfaTenantPolicy(data as Record<string, unknown>);
}

/** Authority: SEC:View. */
export async function listUserSessions(client: EnterpriseMfaQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<UserSession[]> {
  const { data, error } = await client.rpc("list_user_sessions_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseMfaQueryError(error.message);
  }
  return asRows(data).map(parseUserSession);
}

/** Authority: SEC:View. */
export async function listMfaExceptions(client: EnterpriseMfaQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<MfaException[]> {
  const { data, error } = await client.rpc("list_mfa_exceptions_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseMfaQueryError(error.message);
  }
  return asRows(data).map(parseMfaException);
}

/** Authority: SEC:View. Newest first, bounded [1, 200], defaults to 50. */
export async function listMfaStepUpChallenges(client: EnterpriseMfaQueryRpcClient, tenantId: string, actorAuthUserId: string, limit = 50): Promise<MfaStepUpChallenge[]> {
  const { data, error } = await client.rpc("list_mfa_step_up_challenges_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) {
    throw new EnterpriseMfaQueryError(error.message);
  }
  return asRows(data).map(parseMfaStepUpChallenge);
}
