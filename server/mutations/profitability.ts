/**
 * Job, Customer and Service Profitability mutation primitives (FIN-212,
 * CG-S9-FIN-023). A thin, typed wrapper around
 * app.calculate_finance_job_profitability
 * (supabase/migrations/20260729260000_create_finance_job_profitability.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CalculateFinanceJobProfitabilityInputSchema,
  parseFinanceJobProfitabilityFact,
  type CalculateFinanceJobProfitabilityInput,
  type FinanceJobProfitabilityFact,
} from "../contracts/profitability/profitability.ts";

export type ProfitabilityMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PROFITABILITY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "job_order_not_found",
  "finance_profitability_recalculation_reason_required",
] as const;
type KnownProfitabilityMutationErrorCode = (typeof PROFITABILITY_KNOWN_MUTATION_ERROR_CODES)[number];
export type ProfitabilityMutationErrorCode = KnownProfitabilityMutationErrorCode | "mutation_failed" | "invalid_response";

export class ProfitabilityMutationError extends Error {
  readonly code: ProfitabilityMutationErrorCode;

  constructor(code: ProfitabilityMutationErrorCode, message: string) {
    super(message);
    this.name = "ProfitabilityMutationError";
    this.code = code;
  }
}

function classifyError(message: string): ProfitabilityMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (PROFITABILITY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownProfitabilityMutationErrorCode) : "mutation_failed";
}

/**
 * FIN:Edit + FIN:View margin-gated. Resolves billed revenue (every issued
 * invoice for the Job Order) minus approved actual cost (OPS-178), reporting
 * a named blocked_reason rather than a fabricated figure when either source
 * is unavailable or currencies do not reconcile. The first calculation needs
 * no reason; every later recalculation of an existing current fact requires
 * one.
 */
export async function calculateFinanceJobProfitability(
  client: ProfitabilityMutationRpcClient,
  input: CalculateFinanceJobProfitabilityInput,
): Promise<FinanceJobProfitabilityFact> {
  const parsedInput = CalculateFinanceJobProfitabilityInputSchema.parse(input);
  const { data, error } = await client.rpc("calculate_finance_job_profitability", {
    p_job_order_id: parsedInput.jobOrderId,
    p_recalculation_reason: parsedInput.recalculationReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new ProfitabilityMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new ProfitabilityMutationError("invalid_response", "calculate_finance_job_profitability returned no row");
  }
  return parseFinanceJobProfitabilityFact(data as Record<string, unknown>);
}
