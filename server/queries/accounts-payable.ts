/**
 * Accounts Payable read queries (FIN-199, CG-S9-FIN-010). Thin, typed
 * wrappers around app.list_finance_ap_open_items /
 * app.get_finance_ap_open_item_activity / app.get_finance_ap_exposure_summary
 * (supabase/migrations/20260729130000_create_finance_accounts_payable.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceApOpenItem,
  parseFinanceApOpenItemEvent,
  parseFinanceApExposureSummary,
  type FinanceApOpenItem,
  type FinanceApOpenItemEvent,
  type FinanceApExposureSummary,
} from "../contracts/accounts-payable/accounts-payable.ts";

export type AccountsPayableQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class AccountsPayableQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AccountsPayableQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered/sorted list, due_date ascending. */
export async function listFinanceApOpenItems(
  client: AccountsPayableQueryRpcClient,
  input: { tenantId: string; companyId: string | null; vendorMasterId: string | null; status: string | null; overdueOnly: boolean; actorAuthUserId: string },
): Promise<FinanceApOpenItem[]> {
  const { data, error } = await client.rpc("list_finance_ap_open_items", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_vendor_master_id: input.vendorMasterId,
    p_status: input.status,
    p_overdue_only: input.overdueOnly,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AccountsPayableQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceApOpenItem(row as Record<string, unknown>));
}

/** FIN:View-gated. Full append-only activity trail for one open item, oldest first. */
export async function getFinanceApOpenItemActivity(
  client: AccountsPayableQueryRpcClient,
  input: { openItemId: string; actorAuthUserId: string },
): Promise<FinanceApOpenItemEvent[]> {
  const { data, error } = await client.rpc("get_finance_ap_open_item_activity", {
    p_open_item_id: input.openItemId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AccountsPayableQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceApOpenItemEvent(row as Record<string, unknown>));
}

/** FIN:View-gated. Internal Finance vendor-obligation aggregate. */
export async function getFinanceApExposureSummary(
  client: AccountsPayableQueryRpcClient,
  input: { tenantId: string; vendorMasterId: string; actorAuthUserId: string },
): Promise<FinanceApExposureSummary> {
  const { data, error } = await client.rpc("get_finance_ap_exposure_summary", {
    p_tenant_id: input.tenantId,
    p_vendor_master_id: input.vendorMasterId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new AccountsPayableQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AccountsPayableQueryError("get_finance_ap_exposure_summary returned no result");
  }
  return parseFinanceApExposureSummary(data as Record<string, unknown>);
}
