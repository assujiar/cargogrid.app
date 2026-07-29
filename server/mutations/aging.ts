/**
 * AR and AP Aging mutation primitives (FIN-210, CG-S9-FIN-021). A thin,
 * typed wrapper around app.set_finance_aging_bucket_config
 * (supabase/migrations/20260729240000_create_finance_aging.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetFinanceAgingBucketConfigInputSchema,
  parseFinanceAgingBucketConfig,
  type SetFinanceAgingBucketConfigInput,
  type FinanceAgingBucketConfig,
} from "../contracts/aging/aging.ts";

export type AgingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const AGING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "finance_aging_invalid_entity_type",
  "finance_aging_bucket_empty",
  "finance_aging_bucket_missing_field",
  "finance_aging_bucket_first_not_covering_current",
  "finance_aging_bucket_last_not_open_ended",
  "finance_aging_bucket_gap_or_overlap",
] as const;
type KnownAgingMutationErrorCode = (typeof AGING_KNOWN_MUTATION_ERROR_CODES)[number];
export type AgingMutationErrorCode = KnownAgingMutationErrorCode | "mutation_failed" | "invalid_response";

export class AgingMutationError extends Error {
  readonly code: AgingMutationErrorCode;

  constructor(code: AgingMutationErrorCode, message: string) {
    super(message);
    this.name = "AgingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AgingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (AGING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAgingMutationErrorCode) : "mutation_failed";
}

/** FIN:Approve-gated. Validates buckets are non-overlapping, contiguous, first-covers-current and last-open-ended before writing a brand-new, incremented version -- never edits a prior version. */
export async function setFinanceAgingBucketConfig(client: AgingMutationRpcClient, input: SetFinanceAgingBucketConfigInput): Promise<FinanceAgingBucketConfig> {
  const parsedInput = SetFinanceAgingBucketConfigInputSchema.parse(input);
  const { data, error } = await client.rpc("set_finance_aging_bucket_config", {
    p_tenant_id: parsedInput.tenantId,
    p_entity_type: parsedInput.entityType,
    p_buckets: parsedInput.buckets,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new AgingMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new AgingMutationError("invalid_response", "set_finance_aging_bucket_config returned no row");
  }
  return parseFinanceAgingBucketConfig(data as Record<string, unknown>);
}
