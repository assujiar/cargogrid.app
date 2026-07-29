/**
 * Accounts Receivable read queries (FIN-196, CG-S9-FIN-007). Thin, typed
 * wrappers around app.list_finance_ar_open_items /
 * app.get_finance_ar_open_item_activity / app.get_finance_ar_exposure_summary
 * (supabase/migrations/20260729100000_create_finance_accounts_receivable.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceArOpenItem,
  parseFinanceArOpenItemEvent,
  parseFinanceArExposureSummary,
  type FinanceArOpenItem,
  type FinanceArOpenItemEvent,
  type FinanceArExposureSummary,
} from "../contracts/accounts-receivable/accounts-receivable.ts";

export type AccountsReceivableQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class AccountsReceivableQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AccountsReceivableQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered/sorted list, due_date ascending. */
export async function listFinanceArOpenItems(
  client: AccountsReceivableQueryRpcClient,
  input: { tenantId: string; companyId: string | null; customerAccountId: string | null; status: string | null; overdueOnly: boolean; actorAuthUserId: string },
): Promise<FinanceArOpenItem[]> {
  const { data, error } = await client.rpc("list_finance_ar_open_items", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_customer_account_id: input.customerAccountId,
    p_status: input.status,
    p_overdue_only: input.overdueOnly,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AccountsReceivableQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceArOpenItem(row as Record<string, unknown>));
}

/** FIN:View-gated. Full append-only activity trail for one open item, oldest first. */
export async function getFinanceArOpenItemActivity(
  client: AccountsReceivableQueryRpcClient,
  input: { openItemId: string; actorAuthUserId: string },
): Promise<FinanceArOpenItemEvent[]> {
  const { data, error } = await client.rpc("get_finance_ar_open_item_activity", {
    p_open_item_id: input.openItemId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AccountsReceivableQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceArOpenItemEvent(row as Record<string, unknown>));
}

/** FIN:View-gated. Internal Finance credit-exposure aggregate for one customer -- customer-facing visibility is deferred to Step 13. */
export async function getFinanceArExposureSummary(
  client: AccountsReceivableQueryRpcClient,
  input: { tenantId: string; customerAccountId: string; actorAuthUserId: string },
): Promise<FinanceArExposureSummary> {
  const { data, error } = await client.rpc("get_finance_ar_exposure_summary", {
    p_tenant_id: input.tenantId,
    p_customer_account_id: input.customerAccountId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AccountsReceivableQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AccountsReceivableQueryError("get_finance_ar_exposure_summary returned no result");
  }
  return parseFinanceArExposureSummary(data as Record<string, unknown>);
}
