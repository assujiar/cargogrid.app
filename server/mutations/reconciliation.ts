/**
 * Reconciliation mutation primitives (FIN-209, CG-S9-FIN-020). Thin,
 * typed wrappers around app.execute_finance_reconciliation_run /
 * app.resolve_finance_reconciliation_exception /
 * app.certify_finance_reconciliation_run
 * (supabase/migrations/20260729230000_create_finance_reconciliation.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ExecuteFinanceReconciliationRunInputSchema,
  CertifyFinanceReconciliationRunInputSchema,
  ResolveFinanceReconciliationExceptionInputSchema,
  parseFinanceReconciliationRun,
  parseFinanceReconciliationException,
  type ExecuteFinanceReconciliationRunInput,
  type CertifyFinanceReconciliationRunInput,
  type ResolveFinanceReconciliationExceptionInput,
  type FinanceReconciliationRun,
  type FinanceReconciliationException,
} from "../contracts/reconciliation/reconciliation.ts";

export type ReconciliationMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const RECONCILIATION_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_reconciliation_invalid_scope",
  "finance_reconciliation_invalid_tolerance",
  "finance_reconciliation_run_not_found",
  "finance_reconciliation_exception_not_found",
  "finance_reconciliation_exception_not_open",
  "finance_reconciliation_resolution_reason_required",
  "finance_reconciliation_certify_reason_required",
  "finance_reconciliation_unexplained_variance",
  "stale_version",
] as const;
type KnownReconciliationMutationErrorCode = (typeof RECONCILIATION_KNOWN_MUTATION_ERROR_CODES)[number];
export type ReconciliationMutationErrorCode = KnownReconciliationMutationErrorCode | "mutation_failed" | "invalid_response";

export class ReconciliationMutationError extends Error {
  readonly code: ReconciliationMutationErrorCode;

  constructor(code: ReconciliationMutationErrorCode, message: string) {
    super(message);
    this.name = "ReconciliationMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ReconciliationMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (RECONCILIATION_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownReconciliationMutationErrorCode) : "mutation_failed";
}

/** FIN:Edit-gated. Executes a deterministic control-account-vs-open-item comparison as of asOfDate; creates one exception if the variance exceeds toleranceAmount. */
export async function executeFinanceReconciliationRun(client: ReconciliationMutationRpcClient, input: ExecuteFinanceReconciliationRunInput): Promise<FinanceReconciliationRun> {
  const parsedInput = ExecuteFinanceReconciliationRunInputSchema.parse(input);
  const { data, error } = await client.rpc("execute_finance_reconciliation_run", {
    p_tenant_id: parsedInput.tenantId,
    p_company_id: parsedInput.companyId,
    p_scope: parsedInput.scope,
    p_as_of_date: parsedInput.asOfDate,
    p_tolerance_amount: parsedInput.toleranceAmount,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ReconciliationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReconciliationMutationError("invalid_response", "execute_finance_reconciliation_run returned no row");
  }
  return parseFinanceReconciliationRun(data as Record<string, unknown>);
}

/** FIN:Edit-gated. Requires a non-empty resolutionReason; only an open exception may be resolved. */
export async function resolveFinanceReconciliationException(
  client: ReconciliationMutationRpcClient,
  input: ResolveFinanceReconciliationExceptionInput,
): Promise<FinanceReconciliationException> {
  const parsedInput = ResolveFinanceReconciliationExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("resolve_finance_reconciliation_exception", {
    p_exception_id: parsedInput.exceptionId,
    p_expected_version: parsedInput.expectedVersion,
    p_resolution_reason: parsedInput.resolutionReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ReconciliationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReconciliationMutationError("invalid_response", "resolve_finance_reconciliation_exception returned no row");
  }
  return parseFinanceReconciliationException(data as Record<string, unknown>);
}

/** FIN:Approve-gated. Requires zero open exceptions on the run; idempotent once already certified. */
export async function certifyFinanceReconciliationRun(client: ReconciliationMutationRpcClient, input: CertifyFinanceReconciliationRunInput): Promise<FinanceReconciliationRun> {
  const parsedInput = CertifyFinanceReconciliationRunInputSchema.parse(input);
  const { data, error } = await client.rpc("certify_finance_reconciliation_run", {
    p_run_id: parsedInput.runId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ReconciliationMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ReconciliationMutationError("invalid_response", "certify_finance_reconciliation_run returned no row");
  }
  return parseFinanceReconciliationRun(data as Record<string, unknown>);
}
