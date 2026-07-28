/**
 * Chart of Accounts read queries (FIN-192, CG-S9-FIN-003). Thin, typed
 * wrappers around app.list_finance_accounts / app.get_finance_account_dependency_impact
 * (supabase/migrations/20260728210000_create_finance_chart_of_accounts.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceAccount, parseFinanceAccountDependencyImpact, type FinanceAccount, type FinanceAccountDependencyImpact } from "../contracts/chart-of-accounts/chart-of-accounts.ts";

export type ChartOfAccountsQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class ChartOfAccountsQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ChartOfAccountsQueryError";
  }
}

/** Bounded, authority-gated list/tree read (Prompt 192 section 14) -- server-side filtered by tenant/company/status, never a browser-loaded full dataset. */
export async function listFinanceAccounts(
  client: ChartOfAccountsQueryRpcClient,
  input: { tenantId: string; companyId: string | null; status: string | null; actorAuthUserId: string },
): Promise<FinanceAccount[]> {
  const { data, error } = await client.rpc("list_finance_accounts", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_status: input.status,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ChartOfAccountsQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceAccount(row as Record<string, unknown>));
}

/** Dependency-impact preview: active child-account count plus whether any published finance_posting_map item references this account's own code (closes FIN-191's own disclosed forward reference). */
export async function getFinanceAccountDependencyImpact(
  client: ChartOfAccountsQueryRpcClient,
  accountId: string,
  actorAuthUserId: string,
): Promise<FinanceAccountDependencyImpact> {
  const { data, error } = await client.rpc("get_finance_account_dependency_impact", { p_account_id: accountId, p_actor_auth_user_id: actorAuthUserId });
  if (error) {
    throw new ChartOfAccountsQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ChartOfAccountsQueryError("get_finance_account_dependency_impact returned no result");
  }
  return parseFinanceAccountDependencyImpact(data as Record<string, unknown>);
}
