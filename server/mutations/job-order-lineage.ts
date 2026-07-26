/**
 * Full Lineage into Job Order mutation primitive (COM-160, CG-S7-COM-019). Thin,
 * typed wrapper around app.prepare_job_order_handoff
 * (supabase/migrations/20260724340000_create_commercial_job_order_lineage.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { PrepareJobOrderHandoffInputSchema, parseJobOrderHandoff, type PrepareJobOrderHandoffInput, type JobOrderHandoff } from "../contracts/job-order-lineage/job-order-lineage.ts";

export type JobOrderLineageMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const JOB_ORDER_LINEAGE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "quotation_not_found",
  "not_current_version",
  "quote_not_submitted",
  "quote_not_approved",
  "quote_not_accepted",
  "account_not_converted",
] as const;
type KnownJobOrderLineageMutationErrorCode = (typeof JOB_ORDER_LINEAGE_KNOWN_MUTATION_ERROR_CODES)[number];
export type JobOrderLineageMutationErrorCode = KnownJobOrderLineageMutationErrorCode | "mutation_failed" | "invalid_response";

export class JobOrderLineageMutationError extends Error {
  readonly code: JobOrderLineageMutationErrorCode;

  constructor(code: JobOrderLineageMutationErrorCode, message: string) {
    super(message);
    this.name = "JobOrderLineageMutationError";
    this.code = code;
  }
}

function classifyError(message: string): JobOrderLineageMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (JOB_ORDER_LINEAGE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownJobOrderLineageMutationErrorCode)
    : "mutation_failed";
}

/**
 * Idempotent on (tenant, quotation, purpose) -- a retry returns the existing row
 * unchanged. The RPC itself masks its own returned payload/payload_hash per-caller
 * (COM:View selling price), the same "mask the function's own output" technique
 * app.check_customer_credit (COM-157) already established -- app.job_order_handoffs
 * (the base table row type) carries no explicit `payload_masked` column, unlike the
 * directory view, so this wrapper synthesizes it from `payload === null` before parsing.
 */
export async function prepareJobOrderHandoff(client: JobOrderLineageMutationRpcClient, input: PrepareJobOrderHandoffInput): Promise<JobOrderHandoff> {
  const parsedInput = PrepareJobOrderHandoffInputSchema.parse(input);
  const { data, error } = await client.rpc("prepare_job_order_handoff", {
    p_quotation_id: parsedInput.quotationId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new JobOrderLineageMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new JobOrderLineageMutationError("invalid_response", "prepare_job_order_handoff returned no row");
  }
  const row = data as Record<string, unknown>;
  return parseJobOrderHandoff({ ...row, payload_masked: row.payload === null });
}
