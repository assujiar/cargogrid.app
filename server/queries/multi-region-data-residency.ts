/**
 * Multi-Region and Data Residency read queries (IAE-033, Prompt 361). Thin,
 * typed wrappers around app.resolve_tenant_region /
 * app.get_tenant_region_assignment / app.list_region_service_capabilities /
 * app.list_region_capability_exceptions_for_tenant
 * (supabase/migrations/20260808100000_create_intelligence_multi_region_data_residency.sql).
 */

import {
  parseTenantRegionAssignment,
  parseRegionServiceCapability,
  parseRegionCapabilityException,
  RegionCodeSchema,
  type TenantRegionAssignment,
  type RegionServiceCapability,
  type RegionCapabilityException,
  type RegionCode,
} from "../contracts/multi-region-data-residency/multi-region-data-residency.ts";

export interface MultiRegionDataResidencyQueryRpcClient {
  rpc(
    fn:
      | "resolve_tenant_region"
      | "get_tenant_region_assignment"
      | "list_region_service_capabilities"
      | "list_region_capability_exceptions_for_tenant",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class MultiRegionDataResidencyQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "MultiRegionDataResidencyQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** service_role-only -- takes no actor/authority parameter of its own by design (the identical bare-tenant-id shape app.resolve_tenant_deployment_type/app.resolve_retention_days/app.is_high_risk_action already established); call with a trusted server-side client, never an end-user session client. Resolves RPD-013's own real default: 'apac' unless a real region assignment has reached status=active. */
export async function resolveTenantRegion(client: MultiRegionDataResidencyQueryRpcClient, tenantId: string): Promise<RegionCode> {
  const { data, error } = await client.rpc("resolve_tenant_region", { p_tenant_id: tenantId });
  if (error) {
    throw new MultiRegionDataResidencyQueryError(error.message);
  }
  return RegionCodeSchema.parse(data);
}

/** Authority: DEPLOY:View. Returns the tenant's own region assignment, or null if the tenant has none (i.e. is on the apac/default region). */
export async function getTenantRegionAssignment(client: MultiRegionDataResidencyQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<TenantRegionAssignment | null> {
  const { data, error } = await client.rpc("get_tenant_region_assignment", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new MultiRegionDataResidencyQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    return null;
  }
  return parseTenantRegionAssignment(data as Record<string, unknown>);
}

/** Authority: DEPLOY:View against tenantId, used only to prove the caller holds a real grant somewhere -- the returned matrix is platform-wide and identical regardless of tenant. */
export async function listRegionServiceCapabilities(client: MultiRegionDataResidencyQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<RegionServiceCapability[]> {
  const { data, error } = await client.rpc("list_region_service_capabilities", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new MultiRegionDataResidencyQueryError(error.message);
  }
  return asRows(data).map(parseRegionServiceCapability);
}

/** Authority: DEPLOY:View against the tenant's own region assignment. */
export async function listRegionCapabilityExceptions(client: MultiRegionDataResidencyQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<RegionCapabilityException[]> {
  const { data, error } = await client.rpc("list_region_capability_exceptions_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new MultiRegionDataResidencyQueryError(error.message);
  }
  return asRows(data).map(parseRegionCapabilityException);
}
