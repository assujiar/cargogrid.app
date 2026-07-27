/**
 * Job Order mutation primitives (OPS-168, CG-S8-OPS-002). Thin, typed wrappers around
 * app.prepare_job_order / app.confirm_job_order / app.override_job_order_field
 * (supabase/migrations/20260727090000_create_operations_job_order.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  PrepareJobOrderInputSchema,
  ConfirmJobOrderInputSchema,
  OverrideJobOrderFieldInputSchema,
  parseJobOrder,
  type PrepareJobOrderInput,
  type ConfirmJobOrderInput,
  type OverrideJobOrderFieldInput,
  type JobOrder,
} from "../contracts/job-order/job-order.ts";

export type JobOrderMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const JOB_ORDER_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "handoff_not_found",
  "handoff_payload_unavailable",
  "job_order_not_found",
  "stale_version",
  "invalid_transition",
  "invalid_snapshot_column",
  "override_reason_required",
] as const;
type KnownJobOrderMutationErrorCode = (typeof JOB_ORDER_KNOWN_MUTATION_ERROR_CODES)[number];
export type JobOrderMutationErrorCode = KnownJobOrderMutationErrorCode | "mutation_failed" | "invalid_response";

export class JobOrderMutationError extends Error {
  readonly code: JobOrderMutationErrorCode;

  constructor(code: JobOrderMutationErrorCode, message: string) {
    super(message);
    this.name = "JobOrderMutationError";
    this.code = code;
  }
}

function classifyError(message: string): JobOrderMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (JOB_ORDER_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownJobOrderMutationErrorCode)
    : "mutation_failed";
}

async function callAndParseJobOrder(client: JobOrderMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<JobOrder> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new JobOrderMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new JobOrderMutationError("invalid_response", `${fn} returned no row`);
  }
  const row = data as Record<string, unknown>;
  // app.job_orders (the base-table RPC return type) carries no revenue_masked/credit_masked
  // columns, unlike app.job_orders_directory -- synthesize both flags as unmasked (false)
  // rather than coerce them, since the RPC itself never nulls the caller's own written row.
  return parseJobOrder({ revenue_masked: false, credit_masked: false, ...row });
}

/**
 * The one atomic, idempotent conversion action -- a retry, including under a concurrent
 * insert race, returns the exact same Job Order row, never a duplicate. OPS:Create-gated.
 */
export async function prepareJobOrder(client: JobOrderMutationRpcClient, input: PrepareJobOrderInput): Promise<JobOrder> {
  const parsedInput = PrepareJobOrderInputSchema.parse(input);
  return callAndParseJobOrder(client, "prepare_job_order", {
    p_source_handoff_id: parsedInput.sourceHandoffId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/** draft -> confirmed, gated by OPS:Edit. Optimistic-concurrency-checked (expectedVersion). */
export async function confirmJobOrder(client: JobOrderMutationRpcClient, input: ConfirmJobOrderInput): Promise<JobOrder> {
  const parsedInput = ConfirmJobOrderInputSchema.parse(input);
  return callAndParseJobOrder(client, "confirm_job_order", {
    p_job_order_id: parsedInput.jobOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}

/**
 * The one bounded, reasoned, audited post-conversion correction path -- restricted to
 * customerSnapshot/cargoServiceSnapshot (enforced both by the contract's own enum and by
 * app.override_job_order_field itself). Gated by OPS:Override, mandatory non-empty reason.
 */
export async function overrideJobOrderField(client: JobOrderMutationRpcClient, input: OverrideJobOrderFieldInput): Promise<JobOrder> {
  const parsedInput = OverrideJobOrderFieldInputSchema.parse(input);
  return callAndParseJobOrder(client, "override_job_order_field", {
    p_job_order_id: parsedInput.jobOrderId,
    p_expected_version: parsedInput.expectedVersion,
    p_snapshot_column: parsedInput.snapshotColumn,
    p_field_path: parsedInput.fieldPath,
    p_new_value: parsedInput.newValue,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
}
