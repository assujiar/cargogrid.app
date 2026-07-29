/**
 * Reconciliation read queries (FIN-209, CG-S9-FIN-020). Thin, typed
 * wrappers around app.list_finance_reconciliation_runs /
 * app.list_finance_reconciliation_exceptions
 * (supabase/migrations/20260729230000_create_finance_reconciliation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
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
export async function listFinanceReconciliationRuns(
  client: ReconciliationQueryRpcClient,
  input: { tenantId: string; companyId: string | null; scope: string | null; actorAuthUserId: string },
): Promise<FinanceReconciliationRun[]> {
  const { data, error } = await client.rpc("list_finance_reconciliation_runs", {
    p_tenant_id: input.tenantId,
    p_company_id: input.companyId,
    p_scope: input.scope,
    p_actor_auth_user_id: input.actorAuthUserId,
  });
  if (error) {
    throw new ReconciliationQueryError(error.message);
  }
  const rows = Array.isArray(data) ? data : [];
  return rows.map((row) => parseFinanceReconciliationRun(row as Record<string, unknown>));
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
