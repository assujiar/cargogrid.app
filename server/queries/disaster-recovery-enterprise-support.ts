/**
 * Disaster Recovery and Enterprise Support read queries (IAE-035, Prompt
 * 363). Thin, typed wrappers around app.resolve_latest_dr_restore_status /
 * app.list_dr_restore_tests_for_tenant / app.get_support_entitlement /
 * app.get_enterprise_onboarding_checklist
 * (supabase/migrations/20260808300000_create_intelligence_disaster_recovery_enterprise_support.sql).
 */

import {
  parseDrRestoreTest,
  parseSupportEntitlement,
  parseEnterpriseOnboardingChecklist,
  DrTestStatusSchema,
  type DrRestoreTest,
  type SupportEntitlement,
  type EnterpriseOnboardingChecklist,
  type DrComponentScope,
  type DrTestStatus,
} from "../contracts/disaster-recovery-enterprise-support/disaster-recovery-enterprise-support.ts";

export interface DisasterRecoveryEnterpriseSupportQueryRpcClient {
  rpc(
    fn:
      | "resolve_latest_dr_restore_status"
      | "list_dr_restore_tests_for_tenant"
      | "get_support_entitlement"
      | "get_enterprise_onboarding_checklist",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class DisasterRecoveryEnterpriseSupportQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "DisasterRecoveryEnterpriseSupportQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** service_role-only -- takes no actor/authority parameter of its own by design (the identical bare-tenant-id shape app.resolve_tenant_deployment_type/app.resolve_tenant_region/app.resolve_workload_budget already established); call with a trusted server-side client, never an end-user session client. Returns null (never an error) when neither a tenant-specific nor a platform-wide test exists for this componentScope. */
export async function resolveLatestDrRestoreStatus(client: DisasterRecoveryEnterpriseSupportQueryRpcClient, tenantId: string, componentScope: DrComponentScope): Promise<DrTestStatus | null> {
  const { data, error } = await client.rpc("resolve_latest_dr_restore_status", { p_tenant_id: tenantId, p_component_scope: componentScope });
  if (error) {
    throw new DisasterRecoveryEnterpriseSupportQueryError(error.message);
  }
  return data === null ? null : DrTestStatusSchema.parse(data);
}

/** Authority: SUP:View. */
export async function listDrRestoreTests(client: DisasterRecoveryEnterpriseSupportQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<DrRestoreTest[]> {
  const { data, error } = await client.rpc("list_dr_restore_tests_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DisasterRecoveryEnterpriseSupportQueryError(error.message);
  }
  return asRows(data).map(parseDrRestoreTest);
}

/** Authority: SUP:View. Returns the tenant's own support entitlement, or null if none is configured. */
export async function getSupportEntitlement(client: DisasterRecoveryEnterpriseSupportQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<SupportEntitlement | null> {
  const { data, error } = await client.rpc("get_support_entitlement", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DisasterRecoveryEnterpriseSupportQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    return null;
  }
  return parseSupportEntitlement(data as Record<string, unknown>);
}

/** Authority: SUP:View. Returns the tenant's own onboarding checklist, or null if it has never been touched. */
export async function getEnterpriseOnboardingChecklist(client: DisasterRecoveryEnterpriseSupportQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<EnterpriseOnboardingChecklist | null> {
  const { data, error } = await client.rpc("get_enterprise_onboarding_checklist", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new DisasterRecoveryEnterpriseSupportQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    return null;
  }
  return parseEnterpriseOnboardingChecklist(data as Record<string, unknown>);
}
