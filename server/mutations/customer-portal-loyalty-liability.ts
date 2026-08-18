/**
 * Liability Reconciliation Analytics mutation primitives (CPL-323,
 * CG-S13-CPL-025). Thin, typed wrappers around every write RPC in
 * supabase/migrations/20260801250000_create_customer_portal_loyalty_
 * liability_reconciliation_analytics.sql -- all three are staff-only
 * (LYL:Edit/LYL:Configure); this checkpoint adds zero new customer-
 * initiated write (the one customer-facing surface, the consolidated
 * summary, is read-only; see server/queries/customer-portal-loyalty-
 * liability.ts).
 *
 * Mirrors server/mutations/customer-portal-loyalty-expiry-fraud.ts's own
 * known-error-code/classifyError/callRpc shape.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseLoyaltyLiabilityReconciliationRun,
  parseLoyaltyLiabilityReconciliationException,
  ExecuteLoyaltyLiabilityReconciliationRunInputSchema,
  ResolveLoyaltyLiabilityReconciliationExceptionInputSchema,
  CertifyLoyaltyLiabilityReconciliationRunInputSchema,
  type ExecuteLoyaltyLiabilityReconciliationRunInput,
  type ResolveLoyaltyLiabilityReconciliationExceptionInput,
  type CertifyLoyaltyLiabilityReconciliationRunInput,
  type LoyaltyLiabilityReconciliationRun,
  type LoyaltyLiabilityReconciliationException,
} from "../contracts/customer-portal-loyalty-liability/customer-portal-loyalty-liability.ts";

export type LoyaltyLiabilityMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LOYALTY_LIABILITY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_currency",
  "invalid_period",
  "loyalty_liability_reconciliation_run_not_found",
  "loyalty_liability_reconciliation_exception_not_found",
  "loyalty_liability_reconciliation_unresolved_exceptions",
  "reason_required",
  "invalid_transition",
  "stale_version",
  "actor_identity_mismatch",
] as const;
export type KnownLoyaltyLiabilityMutationErrorCode = (typeof LOYALTY_LIABILITY_KNOWN_MUTATION_ERROR_CODES)[number];
export type LoyaltyLiabilityMutationErrorCode = KnownLoyaltyLiabilityMutationErrorCode | "mutation_failed";

export class LoyaltyLiabilityMutationError extends Error {
  readonly code: LoyaltyLiabilityMutationErrorCode;

  constructor(code: LoyaltyLiabilityMutationErrorCode, message: string) {
    super(message);
    this.name = "LoyaltyLiabilityMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LoyaltyLiabilityMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LOYALTY_LIABILITY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLoyaltyLiabilityMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LoyaltyLiabilityMutationRpcClient, fn: string, args: Record<string, unknown>, parse: (row: Record<string, unknown>) => T): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new LoyaltyLiabilityMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new LoyaltyLiabilityMutationError("mutation_failed", `${fn} returned no row`);
  }
  return parse(row as Record<string, unknown>);
}

/** Staff/system, LYL:Edit. Recomputes every liability total LIVE from the raw ledger/event tables. Idempotent on (tenant_id, idempotency_key). */
export async function executeLoyaltyLiabilityReconciliationRun(client: LoyaltyLiabilityMutationRpcClient, input: ExecuteLoyaltyLiabilityReconciliationRunInput): Promise<LoyaltyLiabilityReconciliationRun> {
  const v = ExecuteLoyaltyLiabilityReconciliationRunInputSchema.parse(input);
  return callRpc(
    client,
    "execute_loyalty_liability_reconciliation_run",
    {
      p_tenant_id: v.tenantId,
      p_as_of: v.asOf,
      p_currency: v.currency,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
      p_idempotency_key: v.idempotencyKey,
      p_config_version: v.configVersion,
    },
    parseLoyaltyLiabilityReconciliationRun,
  );
}

/** Staff, LYL:Edit. Mandatory non-empty resolutionReason. Double-defended NULL-bypass optimistic concurrency. */
export async function resolveLoyaltyLiabilityReconciliationException(client: LoyaltyLiabilityMutationRpcClient, input: ResolveLoyaltyLiabilityReconciliationExceptionInput): Promise<LoyaltyLiabilityReconciliationException> {
  const v = ResolveLoyaltyLiabilityReconciliationExceptionInputSchema.parse(input);
  return callRpc(
    client,
    "resolve_loyalty_liability_reconciliation_exception",
    {
      p_tenant_id: v.tenantId,
      p_exception_id: v.exceptionId,
      p_expected_version: v.expectedVersion,
      p_resolution_reason: v.resolutionReason,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyLiabilityReconciliationException,
  );
}

/** Staff, LYL:Configure (governance-grade, the elevated bar) -- BLOCKED while any exception on this run remains open. */
export async function certifyLoyaltyLiabilityReconciliationRun(client: LoyaltyLiabilityMutationRpcClient, input: CertifyLoyaltyLiabilityReconciliationRunInput): Promise<LoyaltyLiabilityReconciliationRun> {
  const v = CertifyLoyaltyLiabilityReconciliationRunInputSchema.parse(input);
  return callRpc(
    client,
    "certify_loyalty_liability_reconciliation_run",
    {
      p_tenant_id: v.tenantId,
      p_run_id: v.runId,
      p_expected_version: v.expectedVersion,
      p_actor_auth_user_id: v.actorAuthUserId,
      p_actor_label: v.actorLabel,
    },
    parseLoyaltyLiabilityReconciliationRun,
  );
}
