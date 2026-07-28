/**
 * Billing Readiness mutation primitives (OPS-181, CG-S8-OPS-015). Thin, typed
 * wrappers around the RPCs in
 * supabase/migrations/20260728140000_create_operations_billing_readiness.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  EvaluateBillingReadinessInputSchema,
  OverrideBillingReadinessInputSchema,
  RevokeBillingReadinessOverrideInputSchema,
  HandoffBillingReadinessInputSchema,
  parseBillingReadinessEvaluation,
  parseBillingReadinessHandoff,
  type EvaluateBillingReadinessInput,
  type OverrideBillingReadinessInput,
  type RevokeBillingReadinessOverrideInput,
  type HandoffBillingReadinessInput,
  type BillingReadinessEvaluation,
  type BillingReadinessHandoff,
} from "../contracts/billing-readiness/billing-readiness.ts";

export type BillingReadinessMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const BILLING_READINESS_KNOWN_MUTATION_ERROR_CODES = [
  "job_order_not_found",
  "billing_readiness_reevaluation_reason_required",
  "billing_readiness_not_evaluated",
  "billing_readiness_override_reason_required",
  "billing_readiness_override_not_needed",
  "billing_readiness_not_overridden",
  "billing_readiness_revoke_reason_required",
  "billing_readiness_not_ready",
  "idempotency_key_required",
  "stale_version",
  "insufficient_authority",
] as const;
type KnownBillingReadinessMutationErrorCode = (typeof BILLING_READINESS_KNOWN_MUTATION_ERROR_CODES)[number];
export type BillingReadinessMutationErrorCode = KnownBillingReadinessMutationErrorCode | "mutation_failed" | "invalid_response";

export class BillingReadinessMutationError extends Error {
  readonly code: BillingReadinessMutationErrorCode;

  constructor(code: BillingReadinessMutationErrorCode, message: string) {
    super(message);
    this.name = "BillingReadinessMutationError";
    this.code = code;
  }
}

function classifyError(message: string): BillingReadinessMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (BILLING_READINESS_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownBillingReadinessMutationErrorCode) : "mutation_failed";
}

/** The first evaluation for a Job Order needs no reason; every subsequent evaluation while a current row already exists requires a non-empty reevaluationReason. Always inserts a brand-new version. */
export async function evaluateBillingReadiness(client: BillingReadinessMutationRpcClient, input: EvaluateBillingReadinessInput): Promise<BillingReadinessEvaluation> {
  const parsedInput = EvaluateBillingReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("evaluate_billing_readiness", {
    p_job_order_id: parsedInput.jobOrderId,
    p_reevaluation_reason: parsedInput.reevaluationReason ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BillingReadinessMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BillingReadinessMutationError("invalid_response", "evaluate_billing_readiness returned no row");
  }
  return parseBillingReadinessEvaluation(data as Record<string, unknown>);
}

/** Bounded to forcing an evaluated not_ready row to an effective ready outcome -- billing_readiness_override_not_needed if already effectively ready. Reason mandatory, optimistic-concurrency-checked. */
export async function overrideBillingReadiness(client: BillingReadinessMutationRpcClient, input: OverrideBillingReadinessInput): Promise<BillingReadinessEvaluation> {
  const parsedInput = OverrideBillingReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("override_billing_readiness", {
    p_job_order_id: parsedInput.jobOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BillingReadinessMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BillingReadinessMutationError("invalid_response", "override_billing_readiness returned no row");
  }
  return parseBillingReadinessEvaluation(data as Record<string, unknown>);
}

/** Restores the evidence-based evaluated_status as the effective outcome -- never re-evaluates evidence itself. Reason mandatory. */
export async function revokeBillingReadinessOverride(client: BillingReadinessMutationRpcClient, input: RevokeBillingReadinessOverrideInput): Promise<BillingReadinessEvaluation> {
  const parsedInput = RevokeBillingReadinessOverrideInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_billing_readiness_override", {
    p_job_order_id: parsedInput.jobOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BillingReadinessMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BillingReadinessMutationError("invalid_response", "revoke_billing_readiness_override returned no row");
  }
  return parseBillingReadinessEvaluation(data as Record<string, unknown>);
}

/** Idempotent on (tenant, jobOrderId, idempotencyKey) -- a genuine retry with the same key returns the exact same handoff row. Requires the current evaluation's effectiveStatus to be ready. */
export async function handoffBillingReadiness(client: BillingReadinessMutationRpcClient, input: HandoffBillingReadinessInput): Promise<BillingReadinessHandoff> {
  const parsedInput = HandoffBillingReadinessInputSchema.parse(input);
  const { data, error } = await client.rpc("handoff_billing_readiness", {
    p_job_order_id: parsedInput.jobOrderId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new BillingReadinessMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new BillingReadinessMutationError("invalid_response", "handoff_billing_readiness returned no row");
  }
  return parseBillingReadinessHandoff(data as Record<string, unknown>);
}
