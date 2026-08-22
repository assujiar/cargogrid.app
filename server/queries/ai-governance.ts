/**
 * AI Governance Provider Boundary queries (IAE-019, Prompt 347). Thin,
 * typed wrappers around app.list_ai_governed_requests_for_tenant /
 * app.get_ai_governed_dispatch_info / app.get_ai_governed_credential
 * (supabase/migrations/20260805060000_create_intelligence_ai_governance_provider_boundary.sql).
 */

import {
  ListAiGovernedRequestsForTenantInputSchema,
  parseAiGovernedRequest,
  parseAiGovernedDispatchInfo,
  type ListAiGovernedRequestsForTenantInput,
  type AiGovernedRequest,
  type AiGovernedDispatchInfo,
} from "../contracts/ai-governance/ai-governance.ts";

export interface AiGovernanceQueryRpcClient {
  rpc(
    fn: "list_ai_governed_requests_for_tenant" | "get_ai_governed_dispatch_info" | "get_ai_governed_credential",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class AiGovernanceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AiGovernanceQueryError";
  }
}

/** Authority: AI:View for the tenant. */
export async function listAiGovernedRequestsForTenant(client: AiGovernanceQueryRpcClient, input: ListAiGovernedRequestsForTenantInput): Promise<AiGovernedRequest[]> {
  const parsedInput = ListAiGovernedRequestsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_ai_governed_requests_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_feature_code: parsedInput.featureCode,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new AiGovernanceQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new AiGovernanceQueryError("list_ai_governed_requests_for_tenant returned a non-array result");
  }
  return data.map((row) => parseAiGovernedRequest(row as Record<string, unknown>));
}

/** The real dispatch client's own minimal read -- never the raw credential. Returns null if no active openai_multimodal connection exists for this tenant. */
export async function getAiGovernedDispatchInfo(client: AiGovernanceQueryRpcClient, tenantId: string, actorAuthUserId: string): Promise<AiGovernedDispatchInfo | null> {
  const { data, error } = await client.rpc("get_ai_governed_dispatch_info", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new AiGovernanceQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseAiGovernedDispatchInfo(row as Record<string, unknown>);
}

/** service_role-only. Returns null if the connection has no stored credential. */
export async function getAiGovernedCredential(client: AiGovernanceQueryRpcClient, connectionId: string): Promise<string | null> {
  const { data, error } = await client.rpc("get_ai_governed_credential", { p_connection_id: connectionId });
  if (error) {
    throw new AiGovernanceQueryError(error.message);
  }
  return typeof data === "string" ? data : null;
}
