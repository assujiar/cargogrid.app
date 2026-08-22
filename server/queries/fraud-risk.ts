/**
 * Fraud and Risk Assistance queries (IAE-024, Prompt 352). Thin, typed
 * wrappers around app.get_risk_signal / app.list_risk_signals_for_tenant
 * (supabase/migrations/20260806300000_create_intelligence_fraud_risk_assistance.sql).
 */

import {
  GetRiskSignalInputSchema,
  ListRiskSignalsForTenantInputSchema,
  parseRiskSignalDetail,
  parseRiskSignalSummary,
  type GetRiskSignalInput,
  type ListRiskSignalsForTenantInput,
  type RiskSignalDetail,
  type RiskSignalSummary,
} from "../contracts/fraud-risk/fraud-risk.ts";

export interface FraudRiskQueryRpcClient {
  rpc(fn: "get_risk_signal" | "list_risk_signals_for_tenant", args: Record<string, unknown>): Promise<{ data: unknown; error: { message: string } | null }>;
}

export class FraudRiskQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FraudRiskQueryError";
  }
}

/** Authority: AI:View. Returns null if the signal does not exist (or belongs to a different tenant than p_tenant_id). Restricted internal data -- no customer-facing caller exists. */
export async function getRiskSignal(client: FraudRiskQueryRpcClient, input: GetRiskSignalInput): Promise<RiskSignalDetail | null> {
  const parsedInput = GetRiskSignalInputSchema.parse(input);
  const { data, error } = await client.rpc("get_risk_signal", {
    p_signal_id: parsedInput.signalId,
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
  });
  if (error) {
    throw new FraudRiskQueryError(error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    return null;
  }
  return parseRiskSignalDetail(row as Record<string, unknown>);
}

/** Authority: AI:View. */
export async function listRiskSignalsForTenant(client: FraudRiskQueryRpcClient, input: ListRiskSignalsForTenantInput): Promise<RiskSignalSummary[]> {
  const parsedInput = ListRiskSignalsForTenantInputSchema.parse(input);
  const { data, error } = await client.rpc("list_risk_signals_for_tenant", {
    p_tenant_id: parsedInput.tenantId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_risk_domain: parsedInput.riskDomain,
    p_status: parsedInput.status,
    p_band: parsedInput.band,
    p_limit: parsedInput.limit,
  });
  if (error) {
    throw new FraudRiskQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new FraudRiskQueryError("list_risk_signals_for_tenant returned a non-array result");
  }
  return data.map((row) => parseRiskSignalSummary(row as Record<string, unknown>));
}
