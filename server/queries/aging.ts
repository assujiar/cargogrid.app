/**
 * AR and AP Aging read queries (FIN-210, CG-S9-FIN-021). Thin, typed
 * wrappers around app.get_finance_aging_report / app.get_finance_aging_summary /
 * app.list_finance_aging_bucket_configs
 * (supabase/migrations/20260729240000_create_finance_aging.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceAgingReportRow,
  parseFinanceAgingSummaryRow,
  parseFinanceAgingBucketConfig,
  type FinanceAgingReportRow,
  type FinanceAgingSummaryRow,
  type FinanceAgingBucketConfig,
} from "../contracts/aging/aging.ts";

export type AgingQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class AgingQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AgingQueryError";
  }
}

/** FIN:View-gated. Every open item as of asOfDate, most-overdue first. Derived only -- never a stored summary balance. */
export async function getFinanceAgingReport(
  client: AgingQueryRpcClient,
  input: { tenantId: string; companyId: string | null; entityType: string; asOfDate: string; includeHeld: boolean; actorAuthUserId: string },
): Promise<FinanceAgingReportRow[]> {
  const { data, error } = await client.rpc("get_finance_aging_report", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_entity_type: input.entityType,
    p_as_of_date: input.asOfDate,
    p_include_held: input.includeHeld,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AgingQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceAgingReportRow(row as Record<string, unknown>));
}

/** FIN:View-gated. Aggregated by bucket/currency; always reconciles exactly to the detail report above. */
export async function getFinanceAgingSummary(
  client: AgingQueryRpcClient,
  input: { tenantId: string; companyId: string | null; entityType: string; asOfDate: string; includeHeld: boolean; actorAuthUserId: string },
): Promise<FinanceAgingSummaryRow[]> {
  const { data, error } = await client.rpc("get_finance_aging_summary", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_entity_type: input.entityType,
    p_as_of_date: input.asOfDate,
    p_include_held: input.includeHeld,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AgingQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceAgingSummaryRow(row as Record<string, unknown>));
}

/** FIN:View-gated. Every bucket-config version for a tenant/entityType, most recent first. */
export async function listFinanceAgingBucketConfigs(
  client: AgingQueryRpcClient,
  input: { tenantId: string; entityType: string | null; actorAuthUserId: string },
): Promise<FinanceAgingBucketConfig[]> {
  const { data, error } = await client.rpc("list_finance_aging_bucket_configs", {
    p_tenant_id: input.tenantId,
    p_entity_type: input.entityType,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AgingQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceAgingBucketConfig(row as Record<string, unknown>));
}
