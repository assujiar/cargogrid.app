/**
 * Cash and Bank Baseline read queries (FIN-211, CG-S9-FIN-022). Thin,
 * typed wrappers around app.list_finance_bank_accounts /
 * app.list_finance_bank_transactions / app.get_finance_cash_position
 * (supabase/migrations/20260729250000_create_finance_cash_bank.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { BOUNDED_LIST_LIMIT } from "./bounded-list.ts";
import {
  parseFinanceBankAccount,
  parseFinanceBankTransaction,
  parseFinanceCashPosition,
  type FinanceBankAccount,
  type FinanceBankTransaction,
  type FinanceCashPosition,
} from "../contracts/cash-bank/cash-bank.ts";

export type CashBankQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class CashBankQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "CashBankQueryError";
  }
}

/**
 * FIN:View-gated. Bounded (200-row default/cap) list, most-recent first.
 * CG-AUDIT-2026-09-02 F3: `afterId`/`limit` optional and additive -- see
 * server/queries/accounts-receivable.ts#listFinanceArOpenItems's own header comment
 * for the full rationale.
 */
export async function listFinanceBankAccounts(
  client: CashBankQueryRpcClient,
  input: { tenantId: string; companyId: string | null; actorAuthUserId: string; limit?: number; afterId?: string | null },
): Promise<FinanceBankAccount[]> {
  const limit = input.limit ?? BOUNDED_LIST_LIMIT;
  const { data, error } = await client.rpc("list_finance_bank_accounts", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_limit: limit,
    p_after_id: input.afterId ?? null,
  });
  if (error) {
    throw new CashBankQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.slice(0, limit).map((row) => parseFinanceBankAccount(row as Record<string, unknown>));
}

/** FIN:View-gated. Bounded (200-row default/cap), server-filtered list, most-recent first. CG-AUDIT-2026-09-02 F3: `afterId`/`limit` optional and additive, same rationale as listFinanceBankAccounts above. */
export async function listFinanceBankTransactions(
  client: CashBankQueryRpcClient,
  input: { tenantId: string; bankAccountId: string | null; matchStatus: string | null; actorAuthUserId: string; limit?: number; afterId?: string | null },
): Promise<FinanceBankTransaction[]> {
  const limit = input.limit ?? BOUNDED_LIST_LIMIT;
  const { data, error } = await client.rpc("list_finance_bank_transactions", {
    p_tenant_id: input.tenantId,
    p_bank_account_id: input.bankAccountId,
    p_match_status: input.matchStatus,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_limit: limit,
    p_after_id: input.afterId ?? null,
  });
  if (error) {
    throw new CashBankQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.slice(0, limit).map((row) => parseFinanceBankTransaction(row as Record<string, unknown>));
}

/** FIN:View-gated. Statement-derived balance versus the account's own GL (cash_default-mapped) balance, as of a fixed date. */
export async function getFinanceCashPosition(
  client: CashBankQueryRpcClient,
  input: { tenantId: string; bankAccountId: string; asOfDate: string; actorAuthUserId: string },
): Promise<FinanceCashPosition> {
  const { data, error } = await client.rpc("get_finance_cash_position", {
    p_tenant_id: input.tenantId,
    p_bank_account_id: input.bankAccountId,
    p_as_of_date: input.asOfDate,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new CashBankQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  const row = rows[0];
  if (!row) {
    throw new CashBankQueryError("get_finance_cash_position returned no row");
  }
  return parseFinanceCashPosition(row as Record<string, unknown>);
}
