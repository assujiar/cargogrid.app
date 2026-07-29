/**
 * Job, Customer and Service Profitability read queries (FIN-212, CG-S9-FIN-023).
 * Thin, typed wrappers around app.get_finance_job_profitability /
 * app.get_finance_profitability_summary
 * (supabase/migrations/20260729260000_create_finance_job_profitability.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceJobProfitabilityFact,
  parseFinanceProfitabilitySummaryRow,
  type FinanceJobProfitabilityFact,
  type FinanceProfitabilitySummaryRow,
} from "../contracts/profitability/profitability.ts";

export type ProfitabilityQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class ProfitabilityQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ProfitabilityQueryError";
  }
}

/**
 * FIN:View margin-gated, deny outright (no partial result). Returns the Job
 * Order's own current profitability fact, or an empty array when none has
 * ever been calculated yet.
 */
export async function getFinanceJobProfitability(
  client: ProfitabilityQueryRpcClient,
  input: { jobOrderId: string; actorAuthUserId: string },
): Promise<FinanceJobProfitabilityFact[]> {
  const { data, error } = await client.rpc("get_finance_job_profitability", {
    p_job_order_id: input.jobOrderId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ProfitabilityQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceJobProfitabilityFact(row as Record<string, unknown>));
}

/**
 * FIN:View margin-gated, deny outright. Grouped, currency-safe aggregation
 * across every calculated, current fact for the tenant -- a blocked fact is
 * excluded, never guessed into a total.
 */
export async function getFinanceProfitabilitySummary(
  client: ProfitabilityQueryRpcClient,
  input: { tenantId: string; groupBy: string; actorAuthUserId: string },
): Promise<FinanceProfitabilitySummaryRow[]> {
  const { data, error } = await client.rpc("get_finance_profitability_summary", {
    p_tenant_id: input.tenantId,
    p_group_by: input.groupBy,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ProfitabilityQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceProfitabilitySummaryRow(row as Record<string, unknown>));
}
