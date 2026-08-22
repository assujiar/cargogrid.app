/**
 * Optimization Assistance queries (IAE-023, Prompt 351). Thin, typed
 * wrappers around app.get_optimization_scenario / app.list_optimization_scenarios_for_tenant
 * (supabase/migrations/20260806200000_create_intelligence_optimization_assistance.sql).
 */

import {
  GetOptimizationScenarioInputSchema,
  ListOptimizationScenariosForTenantInputSchema,
  parseOptimizationScenarioDetail,
  parseOptimizationScenarioSummary,
  type GetOptimizationScenarioInput,
  type ListOptimizationScenariosForTenantInput,
  type OptimizationScenarioDetail,
  type OptimizationScenarioSummary,
} from "../contracts/optimization-assistance/optimization-assistance.ts";

export interface OptimizationAssistanceQueryRpcClient {
  rpc(fn: "get_optimization_scenario" | "list_optimization_scenarios_for_tenant", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class OptimizationAssistanceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "OptimizationAssistanceQueryError";
  }
}

/** Authority: AI:View. Sensitive fields (cost/margin/vendor/rate/price-shaped, at any nesting depth) are masked unless the actor also holds AI:Approve. */
export async function getOptimizationScenario(client: OptimizationAssistanceQueryRpcClient, input: GetOptimizationScenarioInput): Promise<OptimizationScenarioDetail | null> {
  const parsedInput = GetOptimizationScenarioInputSchema.parse(input);
  const { data, error } = await client.rpc("get_optimization_scenario", {
    p_scenario_id: parsedInput.scenarioId,
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new OptimizationAssistanceQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseOptimizationScenarioDetail(row as Record<string, unknown>);
}

/** Authority: AI:View. */
export async function listOptimizationScenariosForTenant(client: OptimizationAssistanceQueryRpcClient, input: ListOptimizationScenariosForTenantInput): Promise<OptimizationScenarioSummary[]> {
  const parsedInput = ListOptimizationScenariosForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_optimization_scenarios_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_scope_type: parsedInput.scopeType,
    p_status: parsedInput.status,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new OptimizationAssistanceQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new OptimizationAssistanceQueryError("list_optimization_scenarios_for_tenant returned a non-array result");
  }
  return data.map((row) => parseOptimizationScenarioSummary(row as Record<string, unknown>));
}
