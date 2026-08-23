/**
 * Scale-Up Architecture read queries (IAE-034, Prompt 362). Thin, typed
 * wrappers around app.resolve_workload_budget /
 * app.get_workload_capacity_profile / app.list_backpressure_events_for_tenant
 * / app.list_scaling_recommendations_for_tenant
 * (supabase/migrations/20260808200000_create_intelligence_scale_up_architecture.sql).
 */

import {
  parseWorkloadCapacityProfile,
  parseWorkloadBackpressureEvent,
  parseScalingRecommendation,
  type WorkloadCapacityProfile,
  type WorkloadBackpressureEvent,
  type ScalingRecommendation,
  type WorkloadType,
} from "../contracts/scale-up-architecture/scale-up-architecture.ts";

export interface ScaleUpArchitectureQueryRpcClient {
  rpc(
    fn:
      | "resolve_workload_budget"
      | "get_workload_capacity_profile"
      | "list_backpressure_events_for_tenant"
      | "list_scaling_recommendations_for_tenant",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class ScaleUpArchitectureQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ScaleUpArchitectureQueryError";
  }
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (!data) {
    return [];
  }
  return Array.isArray(data) ? (data as Record<string, unknown>[]) : [data as Record<string, unknown>];
}

/** service_role-only -- takes no actor/authority parameter of its own by design (the identical bare-tenant-id shape app.resolve_tenant_deployment_type/app.resolve_tenant_region/app.resolve_retention_days already established); call with a trusted server-side client, never an end-user session client. Returns null (never an error) when neither a tenant override nor a platform default is configured for this workloadType. */
export async function resolveWorkloadBudget(client: ScaleUpArchitectureQueryRpcClient, tenantId: string, workloadType: WorkloadType): Promise<number | null> {
  const { data, error } = await client.rpc("resolve_workload_budget", { p_tenant_id: tenantId, p_workload_type: workloadType });
  if (error) {
    throw new ScaleUpArchitectureQueryError(error.message);
  }
  return typeof data === "number" ? data : null;
}

/** Authority: MON:View. Returns the tenant's own capacity profile for this workloadType, or null if none is configured. */
export async function getWorkloadCapacityProfile(client: ScaleUpArchitectureQueryRpcClient, tenantId: string, workloadType: WorkloadType, actorAuthUserId: string): Promise<WorkloadCapacityProfile | null> {
  const { data, error } = await client.rpc("get_workload_capacity_profile", { p_tenant_id: tenantId, p_workload_type: workloadType, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ScaleUpArchitectureQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    return null;
  }
  return parseWorkloadCapacityProfile(data as Record<string, unknown>);
}

/** Authority: MON:View. */
export async function listBackpressureEvents(client: ScaleUpArchitectureQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<WorkloadBackpressureEvent[]> {
  const { data, error } = await client.rpc("list_backpressure_events_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ScaleUpArchitectureQueryError(error.message);
  }
  return asRows(data).map(parseWorkloadBackpressureEvent);
}

/** Authority: MON:View. */
export async function listScalingRecommendations(client: ScaleUpArchitectureQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<ScalingRecommendation[]> {
  const { data, error } = await client.rpc("list_scaling_recommendations_for_tenant", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ScaleUpArchitectureQueryError(error.message);
  }
  return asRows(data).map(parseScalingRecommendation);
}
