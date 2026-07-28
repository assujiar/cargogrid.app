/**
 * Basic Job Profitability mutation primitives (OPS-179, CG-S8-OPS-013). Thin, typed
 * wrapper around app.calculate_job_profitability
 * (supabase/migrations/20260728120000_create_operations_job_profitability.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CalculateJobProfitabilityInputSchema,
  parseJobProfitabilitySnapshot,
  type CalculateJobProfitabilityInput,
  type JobProfitabilitySnapshot,
} from "../contracts/job-profitability/job-profitability.ts";

export type JobProfitabilityMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const JOB_PROFITABILITY_KNOWN_MUTATION_ERROR_CODES = [
  "job_order_not_found",
  "job_profitability_recalculation_reason_required",
  "insufficient_authority",
] as const;
type KnownJobProfitabilityMutationErrorCode = (typeof JOB_PROFITABILITY_KNOWN_MUTATION_ERROR_CODES)[number];
export type JobProfitabilityMutationErrorCode = KnownJobProfitabilityMutationErrorCode | "mutation_failed" | "invalid_response";

export class JobProfitabilityMutationError extends Error {
  readonly code: JobProfitabilityMutationErrorCode;

  constructor(code: JobProfitabilityMutationErrorCode, message: string) {
    super(message);
    this.name = "JobProfitabilityMutationError";
    this.code = code;
  }
}

function classifyError(message: string): JobProfitabilityMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (JOB_PROFITABILITY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownJobProfitabilityMutationErrorCode) : "mutation_failed";
}

/** The first calculation for a job needs no reason; every subsequent recalculation while a current snapshot exists requires a non-empty recalculationReason. */
export async function calculateJobProfitability(client: JobProfitabilityMutationRpcClient, input: CalculateJobProfitabilityInput): Promise<JobProfitabilitySnapshot> {
  const parsedInput = CalculateJobProfitabilityInputSchema.parse(input);
  const { data, error } = await client.rpc("calculate_job_profitability", {
    p_job_order_id: parsedInput.jobOrderId,
    p_recalculation_reason: parsedInput.recalculationReason ?? null,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new JobProfitabilityMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new JobProfitabilityMutationError("invalid_response", "calculate_job_profitability returned no row");
  }
  return parseJobProfitabilitySnapshot(data as Record<string, unknown>);
}
