/**
 * WMS Picking mutation primitives (ATW-017, CG-S10-ATW-017). Thin, typed wrappers
 * around app.create_wms_pick_wave/app.generate_wms_pick_task/app.claim_wms_pick_task/
 * app.confirm_wms_pick_task/app.record_wms_pick_task_short/app.mark_wms_pick_task_
 * exception/app.reassign_wms_pick_task/app.cancel_wms_pick_task/app.approve_wms_pick_
 * substitution
 * (supabase/migrations/20260730240000_create_advanced_tms_wms_picking.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateWmsPickWaveInputSchema,
  GenerateWmsPickTaskInputSchema,
  ClaimWmsPickTaskInputSchema,
  ConfirmWmsPickTaskInputSchema,
  RecordWmsPickTaskShortInputSchema,
  MarkWmsPickTaskExceptionInputSchema,
  ReassignWmsPickTaskInputSchema,
  CancelWmsPickTaskInputSchema,
  ApproveWmsPickSubstitutionInputSchema,
  parseWmsPickWave,
  parseWmsPickTask,
  type CreateWmsPickWaveInput,
  type GenerateWmsPickTaskInput,
  type ClaimWmsPickTaskInput,
  type ConfirmWmsPickTaskInput,
  type RecordWmsPickTaskShortInput,
  type MarkWmsPickTaskExceptionInput,
  type ReassignWmsPickTaskInput,
  type CancelWmsPickTaskInput,
  type ApproveWmsPickSubstitutionInput,
  type WmsPickWave,
  type WmsPickTask,
} from "../contracts/wms-picking/wms-picking.ts";

export type WmsPickingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WMS_PICKING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_idempotency_key",
  "warehouse_not_found",
  "outbound_order_line_not_found",
  "outbound_order_not_confirmed",
  "invalid_quantity",
  "wave_not_found",
  "insufficient_remaining_quantity",
  "location_not_eligible",
  "blocked_location",
  "balance_not_found",
  "insufficient_available_stock",
  "ineligible_stock",
  "no_eligible_pick_location",
  "incompatible_location",
  "task_not_found",
  "stale_version",
  "task_already_claimed",
  "task_not_claimed",
  "task_already_resolved",
  "task_exception",
  "task_cancelled",
  "not_task_claimant",
  "exceeds_remaining_quantity",
  "location_mismatch",
  "item_mismatch",
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
  "has_pick_progress",
  "substitution_not_allowed",
  "substitute_item_not_eligible",
  "invalid_substitution",
  "has_confirmed_quantity",
  "item_not_eligible",
  "serial_conflict",
  "idempotency_key_conflict",
] as const;
type KnownWmsPickingMutationErrorCode = (typeof WMS_PICKING_KNOWN_MUTATION_ERROR_CODES)[number];
export type WmsPickingMutationErrorCode = KnownWmsPickingMutationErrorCode | "mutation_failed" | "invalid_response";

export class WmsPickingMutationError extends Error {
  readonly code: WmsPickingMutationErrorCode;

  constructor(code: WmsPickingMutationErrorCode, message: string) {
    super(message);
    this.name = "WmsPickingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WmsPickingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WMS_PICKING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWmsPickingMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseWaveResponse(data: unknown, rpcName: string): WmsPickWave {
  const row = firstRow(data);
  if (!row) {
    throw new WmsPickingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsPickWave(row);
}

function parseTaskResponse(data: unknown, rpcName: string): WmsPickTask {
  const row = firstRow(data);
  if (!row) {
    throw new WmsPickingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsPickTask(row);
}

/** Idempotent on (tenant_id, idempotency_key). A lightweight, state-machine-free grouping label (design note 2) -- never a lifecycle entity in its own right. */
export async function createWmsPickWave(client: WmsPickingMutationRpcClient, input: CreateWmsPickWaveInput): Promise<WmsPickWave> {
  const parsedInput = CreateWmsPickWaveInputSchema.parse(input);
  const { data, error } = await client.rpc("create_wms_pick_wave", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseWaveResponse(data, "create_wms_pick_wave");
}

/** Real, synchronous, idempotent RPC (no scheduler/worker runtime exists yet, ISS-2026-015) -- idempotent on (tenant_id, idempotency_key), including under a genuine race. Locks the outbound order line row before computing already-allocated quantity -- the double-allocation guard. */
export async function generateWmsPickTask(client: WmsPickingMutationRpcClient, input: GenerateWmsPickTaskInput): Promise<WmsPickTask> {
  const parsedInput = GenerateWmsPickTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_wms_pick_task", {
    p_outbound_order_line_id: parsedInput.outboundOrderLineId,
    p_quantity: parsedInput.quantity,
    p_wave_id: parsedInput.waveId,
    p_location_id: parsedInput.locationId,
    p_lot_number: parsedInput.lotNumber,
    p_serial_number: parsedInput.serialNumber,
    p_suggested_destination_location_id: parsedInput.suggestedDestinationLocationId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "generate_wms_pick_task");
}

/** Idempotent no-op on a same-claimant re-claim. A genuine concurrent double-claim on the same unclaimed task is rejected with task_already_claimed. */
export async function claimWmsPickTask(client: WmsPickingMutationRpcClient, input: ClaimWmsPickTaskInput): Promise<WmsPickTask> {
  const parsedInput = ClaimWmsPickTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("claim_wms_pick_task", {
    p_task_id: parsedInput.taskId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "claim_wms_pick_task");
}

/** Idempotent per-confirm-event on (tenant_id, idempotency_key). The one path that calls app.post_inventory_movement (movement_type=transfer). Only the task's own claimant may confirm it. Confirming less than remaining_quantity is a legitimate partial pick; confirming more is a hard rejection (exceeds_remaining_quantity). */
export async function confirmWmsPickTask(client: WmsPickingMutationRpcClient, input: ConfirmWmsPickTaskInput): Promise<WmsPickTask> {
  const parsedInput = ConfirmWmsPickTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_wms_pick_task", {
    p_task_id: parsedInput.taskId,
    p_quantity: parsedInput.quantity,
    p_scanned_location_id: parsedInput.scannedLocationId,
    p_scanned_item_master_id: parsedInput.scannedItemMasterId,
    p_scanned_lot_number: parsedInput.scannedLotNumber,
    p_scanned_serial_number: parsedInput.scannedSerialNumber,
    p_actual_destination_location_id: parsedInput.actualDestinationLocationId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "confirm_wms_pick_task");
}

/** Prompt 236 section 22's own distinct "record short" alt-flow -- releases exactly the short quantity from app.inventory_balances.reserved, making it available again for a fresh generateWmsPickTask call against the same line. A short beyond remaining_quantity is a hard rejection. */
export async function recordWmsPickTaskShort(client: WmsPickingMutationRpcClient, input: RecordWmsPickTaskShortInput): Promise<WmsPickTask> {
  const parsedInput = RecordWmsPickTaskShortInputSchema.parse(input);
  const { data, error } = await client.rpc("record_wms_pick_task_short", {
    p_task_id: parsedInput.taskId,
    p_short_quantity: parsedInput.shortQuantity,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "record_wms_pick_task_short");
}

/** Callable by the task's own claimant or a supervisor holding OPS:Override. Idempotent no-op on an already-exception task. */
export async function markWmsPickTaskException(client: WmsPickingMutationRpcClient, input: MarkWmsPickTaskExceptionInput): Promise<WmsPickTask> {
  const parsedInput = MarkWmsPickTaskExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("mark_wms_pick_task_exception", {
    p_task_id: parsedInput.taskId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "mark_wms_pick_task_exception");
}

/** OPS:Override supervisor authority. A null newClaimantAuthUserId releases the task back to unclaimed; a non-null one reassigns it. Never callable on an already-resolved (picked/short) or cancelled task. */
export async function reassignWmsPickTask(client: WmsPickingMutationRpcClient, input: ReassignWmsPickTaskInput): Promise<WmsPickTask> {
  const parsedInput = ReassignWmsPickTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("reassign_wms_pick_task", {
    p_task_id: parsedInput.taskId,
    p_new_claimant_auth_user_id: parsedInput.newClaimantAuthUserId,
    p_new_claimant_label: parsedInput.newClaimantLabel,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "reassign_wms_pick_task");
}

/** Only while zero of the task's own picked_quantity/short_quantity has posted -- releases the full original reservation via the shared app.release_inventory_reservation. A task with any real progress may only be completed or reassigned, never cancelled. */
export async function cancelWmsPickTask(client: WmsPickingMutationRpcClient, input: CancelWmsPickTaskInput): Promise<WmsPickTask> {
  const parsedInput = CancelWmsPickTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_wms_pick_task", {
    p_task_id: parsedInput.taskId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "cancel_wms_pick_task");
}

/** OPS:Override-gated governed substitution, only while a task has genuinely zero progress. Releases the original reservation in full and reserves fresh stock against the caller-nominated substitute item (same base_uom_code required), recording one real, auditable app.wms_pick_substitution_approvals row. */
export async function approveWmsPickSubstitution(client: WmsPickingMutationRpcClient, input: ApproveWmsPickSubstitutionInput): Promise<WmsPickTask> {
  const parsedInput = ApproveWmsPickSubstitutionInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_wms_pick_substitution", {
    p_task_id: parsedInput.taskId,
    p_substitute_item_master_id: parsedInput.substituteItemMasterId,
    p_location_id: parsedInput.locationId,
    p_lot_number: parsedInput.lotNumber,
    p_serial_number: parsedInput.serialNumber,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPickingMutationError(classifyError(error.message), error.message);
  }
  return parseTaskResponse(data, "approve_wms_pick_substitution");
}
