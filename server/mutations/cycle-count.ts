/**
 * Cycle Count and Inventory Adjustment mutation primitives (ATW-020, CG-S10-ATW-020).
 * Thin, typed wrappers around app.create_cycle_count_plan/app.freeze_cycle_count_
 * scope/app.cancel_cycle_count_plan/app.close_cycle_count_plan/app.assign_cycle_
 * count_scope_item/app.record_cycle_count_observation/app.approve_cycle_count_
 * variance/app.reject_cycle_count_variance/app.cancel_cycle_count_scope_item
 * (supabase/migrations/20260730270000_create_advanced_tms_cycle_count_adjustment.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateCycleCountPlanInputSchema,
  FreezeCycleCountScopeInputSchema,
  CancelCycleCountPlanInputSchema,
  CloseCycleCountPlanInputSchema,
  AssignCycleCountScopeItemInputSchema,
  RecordCycleCountObservationInputSchema,
  ApproveCycleCountVarianceInputSchema,
  RejectCycleCountVarianceInputSchema,
  CancelCycleCountScopeItemInputSchema,
  parseCycleCountPlan,
  parseCycleCountScopeItem,
  type CreateCycleCountPlanInput,
  type FreezeCycleCountScopeInput,
  type CancelCycleCountPlanInput,
  type CloseCycleCountPlanInput,
  type AssignCycleCountScopeItemInput,
  type RecordCycleCountObservationInput,
  type ApproveCycleCountVarianceInput,
  type RejectCycleCountVarianceInput,
  type CancelCycleCountScopeItemInput,
  type CycleCountPlan,
  type CycleCountScopeItem,
} from "../contracts/cycle-count/cycle-count.ts";

export type CycleCountMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const CYCLE_COUNT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_idempotency_key",
  "warehouse_not_found",
  "invalid_method",
  "invalid_variance_threshold",
  "invalid_recount_threshold",
  "scope_filter_zone_not_found",
  "scope_filter_location_not_found",
  "scope_filter_item_master_not_found",
  "scope_filter_owner_account_not_found",
  "idempotency_key_conflict",
  "plan_not_found",
  "freeze_already_done",
  "stale_version",
  "invalid_transition",
  "invalid_reason",
  "plan_has_unresolved_scope_items",
  "scope_item_not_found",
  "task_not_assignable",
  "task_not_assigned",
  "not_scope_item_claimant",
  "invalid_quantity",
  "location_mismatch",
  "item_mismatch",
  "lot_mismatch",
  "serial_mismatch",
  "uom_conversion_not_registered",
  "task_not_pending_review",
  "self_approval_not_allowed",
  "balance_not_found",
  "balance_changed_since_snapshot",
  "scope_item_already_resolved",
] as const;
type KnownCycleCountMutationErrorCode = (typeof CYCLE_COUNT_KNOWN_MUTATION_ERROR_CODES)[number];
export type CycleCountMutationErrorCode = KnownCycleCountMutationErrorCode | "mutation_failed" | "invalid_response";

export class CycleCountMutationError extends Error {
  readonly code: CycleCountMutationErrorCode;

  constructor(code: CycleCountMutationErrorCode, message: string) {
    super(message);
    this.name = "CycleCountMutationError";
    this.code = code;
  }
}

function classifyError(message: string): CycleCountMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (CYCLE_COUNT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownCycleCountMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parsePlanResponse(data: unknown, rpcName: string): CycleCountPlan {
  const row = firstRow(data);
  if (!row) {
    throw new CycleCountMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseCycleCountPlan(row);
}

function parseScopeItemResponse(data: unknown, rpcName: string): CycleCountScopeItem {
  const row = firstRow(data);
  if (!row) {
    throw new CycleCountMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseCycleCountScopeItem(row);
}

/** Idempotent on (tenant_id, idempotencyKey). Thresholds/requiresSeparateApprover are fixed here for the plan's entire lifetime -- no update RPC exists. */
export async function createCycleCountPlan(client: CycleCountMutationRpcClient, input: CreateCycleCountPlanInput): Promise<CycleCountPlan> {
  const parsedInput = CreateCycleCountPlanInputSchema.parse(input);
  const { data, error } = await client.rpc("create_cycle_count_plan", {
    p_tenant_id: parsedInput.tenantId,
    p_warehouse_id: parsedInput.warehouseId,
    p_method: parsedInput.method ?? null,
    p_variance_threshold_pct: parsedInput.varianceThresholdPct,
    p_recount_threshold_pct: parsedInput.recountThresholdPct,
    p_requires_separate_approver: parsedInput.requiresSeparateApprover ?? null,
    p_scope_filter_zone_id: parsedInput.scopeFilterZoneId ?? null,
    p_scope_filter_location_id: parsedInput.scopeFilterLocationId ?? null,
    p_scope_filter_item_master_id: parsedInput.scopeFilterItemMasterId ?? null,
    p_scope_filter_owner_account_id: parsedInput.scopeFilterOwnerAccountId ?? null,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parsePlanResponse(data, "create_cycle_count_plan");
}

/** draft -> active. Snapshots every matching on-hand balance under the plan's own warehouse (and scope filters); an empty match is a valid, non-error outcome. Returns the newly-created scope items. */
export async function freezeCycleCountScope(client: CycleCountMutationRpcClient, input: FreezeCycleCountScopeInput): Promise<CycleCountScopeItem[]> {
  const parsedInput = FreezeCycleCountScopeInputSchema.parse(input);
  const { data, error } = await client.rpc("freeze_cycle_count_scope", {
    p_plan_id: parsedInput.planId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseCycleCountScopeItem);
}

/** draft/active -> cancelled. Every unresolved scope item under the plan is individually cancelled; approved (adjusted) movements are permanent. */
export async function cancelCycleCountPlan(client: CycleCountMutationRpcClient, input: CancelCycleCountPlanInput): Promise<CycleCountPlan> {
  const parsedInput = CancelCycleCountPlanInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_cycle_count_plan", {
    p_plan_id: parsedInput.planId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parsePlanResponse(data, "cancel_cycle_count_plan");
}

/** active -> closed. Requires every scope item under the plan to be adjusted/no_variance_closed/cancelled (plan_has_unresolved_scope_items otherwise). */
export async function closeCycleCountPlan(client: CycleCountMutationRpcClient, input: CloseCycleCountPlanInput): Promise<CycleCountPlan> {
  const parsedInput = CloseCycleCountPlanInputSchema.parse(input);
  const { data, error } = await client.rpc("close_cycle_count_plan", {
    p_plan_id: parsedInput.planId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parsePlanResponse(data, "close_cycle_count_plan");
}

/** pending|recount_required -> assigned. assigned_to is overwritten even on a recount reassignment. */
export async function assignCycleCountScopeItem(client: CycleCountMutationRpcClient, input: AssignCycleCountScopeItemInput): Promise<CycleCountScopeItem> {
  const parsedInput = AssignCycleCountScopeItemInputSchema.parse(input);
  const { data, error } = await client.rpc("assign_cycle_count_scope_item", {
    p_scope_item_id: parsedInput.scopeItemId,
    p_assignee_auth_user_id: parsedInput.assigneeAuthUserId,
    p_assignee_label: parsedInput.assigneeLabel,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parseScopeItemResponse(data, "assign_cycle_count_scope_item");
}

/** Idempotent per-observation-event on (tenant_id, idempotencyKey). Only the scope item's own assigned counter may submit. observedQuantity=0 is a real, valid observation. */
export async function recordCycleCountObservation(client: CycleCountMutationRpcClient, input: RecordCycleCountObservationInput): Promise<CycleCountScopeItem> {
  const parsedInput = RecordCycleCountObservationInputSchema.parse(input);
  const { data, error } = await client.rpc("record_cycle_count_observation", {
    p_scope_item_id: parsedInput.scopeItemId,
    p_observed_quantity: parsedInput.observedQuantity,
    p_observed_uom_code: parsedInput.observedUomCode,
    p_scanned_location_id: parsedInput.scannedLocationId,
    p_scanned_item_master_id: parsedInput.scannedItemMasterId,
    p_scanned_lot_number: parsedInput.scannedLotNumber ?? null,
    p_scanned_serial_number: parsedInput.scannedSerialNumber ?? null,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parseScopeItemResponse(data, "record_cycle_count_observation");
}

/** pending_review -> adjusted, posting exactly one exact ledger movement (movement_type=adjustment, source_type=cycle_count) -- never a direct balance write. Idempotent: a same-item retry after success returns the identical row, never re-posts. */
export async function approveCycleCountVariance(client: CycleCountMutationRpcClient, input: ApproveCycleCountVarianceInput): Promise<CycleCountScopeItem> {
  const parsedInput = ApproveCycleCountVarianceInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_cycle_count_variance", {
    p_scope_item_id: parsedInput.scopeItemId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parseScopeItemResponse(data, "approve_cycle_count_variance");
}

/** pending_review -> recount_required. Never sets reviewedBy/reviewedAt/reviewReason (reserved for a real adjusted resolution). */
export async function rejectCycleCountVariance(client: CycleCountMutationRpcClient, input: RejectCycleCountVarianceInput): Promise<CycleCountScopeItem> {
  const parsedInput = RejectCycleCountVarianceInputSchema.parse(input);
  const { data, error } = await client.rpc("reject_cycle_count_variance", {
    p_scope_item_id: parsedInput.scopeItemId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parseScopeItemResponse(data, "reject_cycle_count_variance");
}

/** Any pre-resolution status -> cancelled. Idempotent no-op if already cancelled. Rejects scope_item_already_resolved for an adjusted or no_variance_closed item. */
export async function cancelCycleCountScopeItem(client: CycleCountMutationRpcClient, input: CancelCycleCountScopeItemInput): Promise<CycleCountScopeItem> {
  const parsedInput = CancelCycleCountScopeItemInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_cycle_count_scope_item", {
    p_scope_item_id: parsedInput.scopeItemId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new CycleCountMutationError(classifyError(error.message), error.message);
  }
  return parseScopeItemResponse(data, "cancel_cycle_count_scope_item");
}
