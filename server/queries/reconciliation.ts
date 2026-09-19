/**
 * Reconciliation read queries (FIN-209, CG-S9-FIN-020). Thin, typed
 * wrappers around app.list_finance_reconciliation_runs /
 * app.list_finance_reconciliation_exceptions
 * (supabase/migrations/20260729230000_create_finance_reconciliation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { BOUNDED_LIST_LIMIT } from "./bounded-list.ts";
import {
  parseFinanceReconciliationRun,
  parseFinanceReconciliationException,
  type FinanceReconciliationRun,
  type FinanceReconciliationException,
} from "../contracts/reconciliation/reconciliation.ts";

export type ReconciliationQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class ReconciliationQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ReconciliationQueryError";
  }
}

/** FIN:View-gated. Bounded (200-row), server-filtered list, most-recent first. */
/** CG-AUDIT-2026-09-02 F3: `afterId`/`limit` optional and additive -- see server/queries/accounts-receivable.ts#listFinanceArOpenItems's own header comment for the full rationale. */
export async function listFinanceReconciliationRuns(
  client: ReconciliationQueryRpcClient,
  input: { tenantId: string; companyId: string | null; scope: string | null; actorAuthUserId: string; limit?: number; afterId?: string | null },
): Promise<FinanceReconciliationRun[]> {
  const limit = input.limit ?? BOUNDED_LIST_LIMIT;
  const { data, error } = await client.rpc("list_finance_reconciliation_runs", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_scope: input.scope,
    p_actor_auth_user_id: input.actorAuthUserId,
    p_limit: limit,
    p_after_id: input.afterId ?? null,
  });
  if (error) {
    throw new ReconciliationQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.slice(0, limit).map((row) => parseFinanceReconciliationRun(row as Record<string, unknown>));
}

/** FIN:View-gated. Every exception for one run, oldest first. */
export async function listFinanceReconciliationExceptions(
  client: ReconciliationQueryRpcClient,
  input: { runId: string; actorAuthUserId: string },
): Promise<FinanceReconciliationException[]> {
  const { data, error } = await client.rpc("list_finance_reconciliation_exceptions", {
    p_run_id: input.runId,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ReconciliationQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceReconciliationException(row as Record<string, unknown>));
}
