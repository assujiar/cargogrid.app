/**
 * Enterprise IAM read queries (IAE-026, Prompt 354). Thin, typed wrappers
 * around app.list_enterprise_idp_connections_for_tenant /
 * app.list_enterprise_sso_domain_claims_for_tenant /
 * app.list_enterprise_sso_login_attempts_for_tenant /
 * app.list_scim_provisioning_events_for_tenant / app.resolve_enterprise_idp_by_email_domain
 * (supabase/migrations/20260807000000_create_intelligence_enterprise_iam_sso.sql).
 * RPC-only, not a direct table `.from()` read -- every new table this
 * capability owns has zero authenticated/anon grant by design (RLS
 * default-deny, mirroring every prior Phase 9 capability since IAE-021).
 */

import { parseIntegrationConnection, type IntegrationConnection } from "../contracts/integration-hub/integration-hub.ts";
import { parseIamDomainClaim, parseIamSsoLoginAttempt, parseIamScimProvisioningEvent, parseEnterpriseIdpByEmailDomain, type IamDomainClaim, type IamSsoLoginAttempt, type IamScimProvisioningEvent, type EnterpriseIdpByEmailDomain } from "../contracts/enterprise-iam/enterprise-iam.ts";

export interface EnterpriseIamQueryRpcClient {
  rpc(
    fn:
      | "list_enterprise_idp_connections_for_tenant"
      | "list_enterprise_sso_domain_claims_for_tenant"
      | "list_enterprise_sso_login_attempts_for_tenant"
      | "list_scim_provisioning_events_for_tenant"
      | "resolve_enterprise_idp_by_email_domain",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class EnterpriseIamQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "EnterpriseIamQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** Authority: IAM:View. Both enterprise_sso_oidc and enterprise_sso_saml connections for one tenant. */
export async function listEnterpriseIdpConnections(client: EnterpriseIamQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<IntegrationConnection[]> {
  const { data, error } = await client.rpc("list_enterprise_idp_connections_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseIamQueryError(error.message);
  }
  return asRows(data).map(parseIntegrationConnection);
}

/** Authority: IAM:View. */
export async function listEnterpriseSsoDomainClaims(client: EnterpriseIamQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<IamDomainClaim[]> {
  const { data, error } = await client.rpc("list_enterprise_sso_domain_claims_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new EnterpriseIamQueryError(error.message);
  }
  return asRows(data).map(parseIamDomainClaim);
}

/** Authority: IAM:View. Newest first, bounded [1, 200], defaults to 50. */
export async function listEnterpriseSsoLoginAttempts(client: EnterpriseIamQueryRpcClient, tenantId: string, actorAuthUserId: string, limit = 50): Promise<IamSsoLoginAttempt[]> {
  const { data, error } = await client.rpc("list_enterprise_sso_login_attempts_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) {
    throw new EnterpriseIamQueryError(error.message);
  }
  return asRows(data).map(parseIamSsoLoginAttempt);
}

/** Authority: IAM:View. Newest first, bounded [1, 200], defaults to 50. */
export async function listScimProvisioningEvents(client: EnterpriseIamQueryRpcClient, tenantId: string, actorAuthUserId: string, limit = 50): Promise<IamScimProvisioningEvent[]> {
  const { data, error } = await client.rpc("list_scim_provisioning_events_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_limit: limit });
  if (error) {
    throw new EnterpriseIamQueryError(error.message);
  }
  return asRows(data).map(parseIamScimProvisioningEvent);
}

/** Deliberately public (no actor required) -- returns null when no active domain claim + active connection exists for this email domain. */
export async function resolveEnterpriseIdpByEmailDomain(client: EnterpriseIamQueryRpcClient, emailDomain: string): Promise<EnterpriseIdpByEmailDomain | null> {
  const { data, error } = await client.rpc("resolve_enterprise_idp_by_email_domain", { p_email_domain: emailDomain });
  if (error) {
    throw new EnterpriseIamQueryError(error.message);
  }
  const [row] = asRows(data);
  if (!row) {
    return null;
  }
  return parseEnterpriseIdpByEmailDomain(row);
}
