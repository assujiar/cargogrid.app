/**
 * Transaction Lineage read queries (OPS-184, CG-S8-OPS-018). Thin, typed wrappers
 * around app.get_transaction_lineage/app.detect_transaction_lineage_anomalies -- both
 * `security definer` with their own explicit access checks (record-scope for the
 * manifest, OPS:Override for the reconciliation diagnostic), so this layer adds no
 * further access check of its own, only shape parsing and the same real query-budget
 * timeout (RPD-014) every other Operations read query already established.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  GetTransactionLineageInputSchema,
  DetectTransactionLineageAnomaliesInputSchema,
  parseTransactionLineageManifest,
  parseTransactionLineageAnomaly,
  type GetTransactionLineageInput,
  type DetectTransactionLineageAnomaliesInput,
  type TransactionLineageManifest,
  type TransactionLineageAnomaly,
} from "../contracts/transaction-lineage/transaction-lineage.ts";

export type TransactionLineageQueryRpcClient = Pick<SupabaseClient, "rpc">;

export class TransactionLineageQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TransactionLineageQueryError";
  }
}

/** Thrown when a lineage RPC does not resolve within its query budget -- never a silently-hung request. */
export class TransactionLineageQueryTimeoutError extends TransactionLineageQueryError {
  constructor(rpcName: string, budgetMs: number) {
    super(`${rpcName} exceeded its ${budgetMs}ms query budget`);
    this.name = "TransactionLineageQueryTimeoutError";
  }
}

/** RPD-014's own "read-only queries, ... timeouts" live-OLTP control. */
export const DEFAULT_TRANSACTION_LINEAGE_QUERY_BUDGET_MS = 5000;

export type TransactionLineageQueryOptions = {
  budgetMs?: number;
};

function withQueryBudget<T>(pending: PromiseLike<T>, rpcName: string, budgetMs: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new TransactionLineageQueryTimeoutError(rpcName, budgetMs)), budgetMs);
    Promise.resolve(pending).then(
      (value) => {
        clearTimeout(timer);
        resolve(value);
      },
      (err: unknown) => {
        clearTimeout(timer);
        reject(err);
      },
    );
  });
}

function resolveBudgetMs(options?: TransactionLineageQueryOptions): number {
  return options?.budgetMs ?? DEFAULT_TRANSACTION_LINEAGE_QUERY_BUDGET_MS;
}

/** The full quote-to-billing lineage manifest for one Job Order -- every hop filtered through app.can_access_record; an inaccessible shipment (and everything hanging off it) is silently omitted, never surfaced as a placeholder. */
export async function getTransactionLineage(
  client: TransactionLineageQueryRpcClient,
  input: GetTransactionLineageInput,
  options?: TransactionLineageQueryOptions,
): Promise<TransactionLineageManifest> {
  const parsedInput = GetTransactionLineageInputSchema.parse(input);
  const { data, error } = await withQueryBudget(
    client.rpc("get_transaction_lineage", { p_job_order_id: parsedInput.jobOrderId, p_actor_auth_user_id: parsedInput.actorAuthUserId }),
    "get_transaction_lineage",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new TransactionLineageQueryError(error.message);
  }
  return parseTransactionLineageManifest(data);
}

/** OPS:Override-gated reconciliation diagnostic -- orphan Shipment Orders/billing-readiness evaluations, duplicate targets, cross-tenant mismatches. Read-only; never mutates anything itself. */
export async function detectTransactionLineageAnomalies(
  client: TransactionLineageQueryRpcClient,
  input: DetectTransactionLineageAnomaliesInput,
  options?: TransactionLineageQueryOptions,
): Promise<TransactionLineageAnomaly[]> {
  const parsedInput = DetectTransactionLineageAnomaliesInputSchema.parse(input);
  const { data, error } = await withQueryBudget(
    client.rpc("detect_transaction_lineage_anomalies", { p_tenant_id: parsedInput.tenantId, p_actor_auth_user_id: parsedInput.actorAuthUserId }),
    "detect_transaction_lineage_anomalies",
    resolveBudgetMs(options),
  );
  if (error) {
    throw new TransactionLineageQueryError(error.message);
  }
  if (!Array.isArray(data)) {
    throw new TransactionLineageQueryError("detect_transaction_lineage_anomalies returned a non-array result");
  }
  return data.map((row) => parseTransactionLineageAnomaly(row as Record<string, unknown>));
}
