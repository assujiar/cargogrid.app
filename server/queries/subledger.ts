/**
 * Subledger read queries (FIN-202, CG-S9-FIN-013). Thin, typed wrappers
 * around app.list_finance_subledger_batches / app.get_finance_subledger_lines /
 * app.get_finance_subledger_reconciliation_summary
 * (supabase/migrations/20260729160000_create_finance_subledger.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseFinanceSubledgerBatch,
  parseFinanceSubledgerLine,
  parseFinanceSubledgerReconciliationSummary,
  type FinanceSubledgerBatch,
  type FinanceSubledgerLine,
  type FinanceSubledgerReconciliationSummary,
} from "../contracts/subledger/subledger.ts";

export type SubledgerQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class SubledgerQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SubledgerQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
export async function listFinanceSubledgerBatches(
  client: SubledgerQueryRpcClient,
  input: { tenantId: string; companyId: string | null; sourceType: string | null; actorAuthUserId: string },
): Promise<FinanceSubledgerBatch[]> {
  const { data, error } = await client.rpc("list_finance_subledger_batches", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_source_type: input.sourceType,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new SubledgerQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceSubledgerBatch(row as Record<string, unknown>));
}

/** FIN:View-gated. Every debit/credit line for one batch, ordered by line_number. */
export async function getFinanceSubledgerLines(
  client: SubledgerQueryRpcClient,
  input: { batchId: string; actorAuthUserId: string },
): Promise<FinanceSubledgerLine[]> {
  const { data, error } = await client.rpc("get_finance_subledger_lines", {
    p_batch_id: input.batchId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new SubledgerQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceSubledgerLine(row as Record<string, unknown>));
}

/** FIN:View-gated. Compares the subledger's own posted AR/AP control-account balances against FIN-196/FIN-199's own live open-item totals. */
export async function getFinanceSubledgerReconciliationSummary(
  client: SubledgerQueryRpcClient,
  input: { tenantId: string; actorAuthUserId: string },
): Promise<FinanceSubledgerReconciliationSummary> {
  const { data, error } = await client.rpc("get_finance_subledger_reconciliation_summary", {
    p_tenant_id: input.tenantId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new SubledgerQueryError(error.message);
  }
  if (!data || typeof data !== "object") {
    throw new SubledgerQueryError("get_finance_subledger_reconciliation_summary returned no result");
  }
  return parseFinanceSubledgerReconciliationSummary(data as Record<string, unknown>);
}
