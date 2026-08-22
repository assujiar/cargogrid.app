/**
 * Dedicated Enterprise Deployment read queries (IAE-032, Prompt 360). Thin,
 * typed wrappers around app.resolve_tenant_deployment_type /
 * app.get_tenant_deployment_record / app.list_deployment_environment_refs
 * (supabase/migrations/20260808000000_create_intelligence_dedicated_enterprise_deployment.sql).
 */

import {
  parseTenantDeploymentRecord,
  parseTenantDeploymentEnvironmentRef,
  ResolvedDeploymentTypeSchema,
  type TenantDeploymentRecord,
  type TenantDeploymentEnvironmentRef,
  type ResolvedDeploymentType,
} from "../contracts/dedicated-enterprise-deployment/dedicated-enterprise-deployment.ts";

export interface DedicatedEnterpriseDeploymentQueryRpcClient {
  rpc(
    fn: "resolve_tenant_deployment_type" | "get_tenant_deployment_record" | "list_deployment_environment_refs",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class DedicatedEnterpriseDeploymentQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DedicatedEnterpriseDeploymentQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** service_role-only -- takes no actor/authority parameter of its own by design (the identical bare-tenant-id shape app.resolve_retention_days/app.is_high_risk_action already established); call with a trusted server-side client, never an end-user session client. Resolves RPD-011's own real default: 'shared' unless a real deployment record has reached status=active. */
export async function resolveTenantDeploymentType(client: DedicatedEnterpriseDeploymentQueryRpcClient, tenantId: string): Promise<ResolvedDeploymentType> {
  const { data, error } = await client.rpc("resolve_tenant_deployment_type", { p_tenant_id: tenantId });
  if (error) {
    throw new DedicatedEnterpriseDeploymentQueryError(error.message);
  }
  return ResolvedDeploymentTypeSchema.parse(data);
}

/** Authority: DEPLOY:View. Returns the tenant's own deployment record, or null if the tenant has none (i.e. is on the shared/default deployment). */
export async function getTenantDeploymentRecord(client: DedicatedEnterpriseDeploymentQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<TenantDeploymentRecord | null> {
  const { data, error } = await client.rpc("get_tenant_deployment_record", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DedicatedEnterpriseDeploymentQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    return null;
  }
  return parseTenantDeploymentRecord(data as Record<string, unknown>);
}

/** Authority: DEPLOY:View against the deployment record's own tenant. */
export async function listDeploymentEnvironmentRefs(client: DedicatedEnterpriseDeploymentQueryRpcClient, deploymentRecordId: string, actorAuthUserId: string): Promise<TenantDeploymentEnvironmentRef[]> {
  const { data, error } = await client.rpc("list_deployment_environment_refs", { p_deployment_record_id: deploymentRecordId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DedicatedEnterpriseDeploymentQueryError(error.message);
  }
  return asRows(data).map(parseTenantDeploymentEnvironmentRef);
}
