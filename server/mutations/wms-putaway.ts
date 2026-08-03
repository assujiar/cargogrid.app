/**
 * WMS Putaway mutation primitives (ATW-014, CG-S10-ATW-014). Thin, typed wrappers
 * around app.generate_wms_putaway_task/app.claim_wms_putaway_task/
 * app.confirm_wms_putaway_task/app.mark_wms_putaway_task_exception/
 * app.reassign_wms_putaway_task/app.cancel_wms_putaway_task
 * (supabase/migrations/20260730210000_create_advanced_tms_wms_putaway.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  GenerateWmsPutawayTaskInputSchema,
  ClaimWmsPutawayTaskInputSchema,
  ConfirmWmsPutawayTaskInputSchema,
  MarkWmsPutawayTaskExceptionInputSchema,
  ReassignWmsPutawayTaskInputSchema,
  CancelWmsPutawayTaskInputSchema,
  parseWmsPutawayTask,
  type GenerateWmsPutawayTaskInput,
  type ClaimWmsPutawayTaskInput,
  type ConfirmWmsPutawayTaskInput,
  type MarkWmsPutawayTaskExceptionInput,
  type ReassignWmsPutawayTaskInput,
  type CancelWmsPutawayTaskInput,
  type WmsPutawayTask,
} from "../contracts/wms-putaway/wms-putaway.ts";

export type WmsPutawayMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WMS_PUTAWAY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_idempotency_key",
  "receipt_line_not_found",
  "receipt_line_not_committed",
  "invalid_quantity",
  "insufficient_remaining_quantity",
  "incompatible_location",
  "task_not_found",
  "stale_version",
  "task_already_claimed",
  "task_not_claimed",
  "task_already_confirmed",
  "task_exception",
  "task_cancelled",
  "not_task_claimant",
  "exceeds_remaining_quantity",
  "missing_lot",
  "lot_mismatch",
  "missing_serial",
  "serial_mismatch",
  "destination_mismatch",
  "location_not_found",
  "blocked_destination",
  "destination_full",
  "invalid_reason",
  "invalid_transition",
  "has_confirmed_quantity",
  "insufficient_stock",
  "item_not_eligible",
  "location_not_eligible",
  "serial_conflict",
  "warehouse_not_found",
] as const;
type KnownWmsPutawayMutationErrorCode = (typeof WMS_PUTAWAY_KNOWN_MUTATION_ERROR_CODES)[number];
export type WmsPutawayMutationErrorCode = KnownWmsPutawayMutationErrorCode | "mutation_failed" | "invalid_response";

export class WmsPutawayMutationError extends Error {
  readonly code: WmsPutawayMutationErrorCode;

  constructor(code: WmsPutawayMutationErrorCode, message: string) {
    super(message);
    this.name = "WmsPutawayMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WmsPutawayMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WMS_PUTAWAY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWmsPutawayMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseTaskResponse(data: unknown, rpcName: string): WmsPutawayTask {
  const row = firstRow(data);
  if (!row) {
    throw new WmsPutawayMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsPutawayTask(row);
}

/** Real, synchronous, idempotent RPC (no scheduler/worker runtime exists yet, ISS-2026-015) -- idempotent on (tenant_id, idempotency_key), including under a genuine race. */
export async function generateWmsPutawayTask(client: WmsPutawayMutationRpcClient, input: GenerateWmsPutawayTaskInput): Promise<WmsPutawayTask> {
  const parsedInput = GenerateWmsPutawayTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_wms_putaway_task", {
    p_receipt_line_id: parsedInput.receiptLineId,
    p_quantity: parsedInput.quantity,
    p_suggested_location_id: parsedInput.suggestedLocationId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPutawayMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "generate_wms_putaway_task");
}

/** Idempotent no-op on a same-claimant re-claim. A genuine concurrent double-claim on the same unclaimed task is rejected with task_already_claimed. */
export async function claimWmsPutawayTask(client: WmsPutawayMutationRpcClient, input: ClaimWmsPutawayTaskInput): Promise<WmsPutawayTask> {
  const parsedInput = ClaimWmsPutawayTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("claim_wms_putaway_task", {
    p_task_id: parsedInput.taskId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPutawayMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "claim_wms_putaway_task");
}

/** Idempotent per-confirm-event on (tenant_id, idempotency_key). The one path that calls app.post_inventory_movement (movement_type=transfer). Only the task's own claimant may confirm it. */
export async function confirmWmsPutawayTask(client: WmsPutawayMutationRpcClient, input: ConfirmWmsPutawayTaskInput): Promise<WmsPutawayTask> {
  const parsedInput = ConfirmWmsPutawayTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_wms_putaway_task", {
    p_task_id: parsedInput.taskId,
    p_quantity: parsedInput.quantity,
    p_actual_location_id: parsedInput.actualLocationId,
    p_lot_number: parsedInput.lotNumber,
    p_serial_number: parsedInput.serialNumber,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPutawayMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "confirm_wms_putaway_task");
}

/** Callable by the task's own claimant or a supervisor holding OPS:Override. Idempotent no-op on an already-exception task. */
export async function markWmsPutawayTaskException(client: WmsPutawayMutationRpcClient, input: MarkWmsPutawayTaskExceptionInput): Promise<WmsPutawayTask> {
  const parsedInput = MarkWmsPutawayTaskExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("mark_wms_putaway_task_exception", {
    p_task_id: parsedInput.taskId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPutawayMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "mark_wms_putaway_task_exception");
}

/** OPS:Override supervisor authority. A null newClaimantAuthUserId releases the task back to unclaimed; a non-null one reassigns it. Never callable on an already-confirmed or cancelled task. */
export async function reassignWmsPutawayTask(client: WmsPutawayMutationRpcClient, input: ReassignWmsPutawayTaskInput): Promise<WmsPutawayTask> {
  const parsedInput = ReassignWmsPutawayTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("reassign_wms_putaway_task", {
    p_task_id: parsedInput.taskId,
    p_new_claimant_auth_user_id: parsedInput.newClaimantAuthUserId,
    p_new_claimant_label: parsedInput.newClaimantLabel,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPutawayMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "reassign_wms_putaway_task");
}

/** Only while zero of the task's own confirmed_quantity has posted -- once real inventory has transferred, the task can only be completed or reassigned, never cancelled. */
export async function cancelWmsPutawayTask(client: WmsPutawayMutationRpcClient, input: CancelWmsPutawayTaskInput): Promise<WmsPutawayTask> {
  const parsedInput = CancelWmsPutawayTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_wms_putaway_task", {
    p_task_id: parsedInput.taskId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPutawayMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "cancel_wms_putaway_task");
}
