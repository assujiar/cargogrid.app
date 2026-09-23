/**
 * Finance Account Ledger read query (CG-AUDIT-2026-09-02 B2, GL detail
 * report half). Thin, typed wrapper around app.get_finance_account_ledger
 * (supabase/migrations/20260922020000_b2_finance_account_ledger.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { parseFinanceAccountLedgerEntry, type FinanceAccountLedgerEntry } from "../contracts/finance-account-ledger/finance-account-ledger.ts";

export type FinanceAccountLedgerQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class FinanceAccountLedgerQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "FinanceAccountLedgerQueryError";
  }
}

/** FIN:View-gated. One account's own posted transaction history for a date range, one row per currency actually posted (never blended), each with a per-currency opening balance and running total. */
export async function getFinanceAccountLedger(
  client: FinanceAccountLedgerQueryRpcClient,
  input: { tenantId: string; companyId: string | null; accountId: string; dateFrom: string; dateTo: string; actorAuthUserId: string },
): Promise<FinanceAccountLedgerEntry[]> {
  const { data, error } = await client.rpc("get_finance_account_ledger", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_account_id: input.accountId,
    p_date_from: input.dateFrom,
    p_date_to: input.dateTo,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new FinanceAccountLedgerQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceAccountLedgerEntry(row as Record<string, unknown>));
}
