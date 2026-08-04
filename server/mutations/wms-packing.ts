/**
 * WMS Packing mutation primitives (ATW-018, CG-S10-ATW-018). Thin, typed wrappers
 * around app.start_wms_packing_task/app.create_wms_package/app.reparent_wms_package/
 * app.add_wms_package_line/app.remove_wms_package_line/
 * app.record_wms_package_measurements/app.record_wms_package_qc/
 * app.override_wms_package_qc_hold/app.record_wms_package_seal/
 * app.confirm_wms_package/app.reopen_wms_package
 * (supabase/migrations/20260730250000_create_advanced_tms_wms_packing.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  StartWmsPackingTaskInputSchema,
  CreateWmsPackageInputSchema,
  ReparentWmsPackageInputSchema,
  AddWmsPackageLineInputSchema,
  RemoveWmsPackageLineInputSchema,
  RecordWmsPackageMeasurementsInputSchema,
  RecordWmsPackageQcInputSchema,
  OverrideWmsPackageQcHoldInputSchema,
  RecordWmsPackageSealInputSchema,
  ConfirmWmsPackageInputSchema,
  ReopenWmsPackageInputSchema,
  parseWmsPackingTask,
  parseWmsPackage,
  type StartWmsPackingTaskInput,
  type CreateWmsPackageInput,
  type ReparentWmsPackageInput,
  type AddWmsPackageLineInput,
  type RemoveWmsPackageLineInput,
  type RecordWmsPackageMeasurementsInput,
  type RecordWmsPackageQcInput,
  type OverrideWmsPackageQcHoldInput,
  type RecordWmsPackageSealInput,
  type ConfirmWmsPackageInput,
  type ReopenWmsPackageInput,
  type WmsPackingTask,
  type WmsPackage,
} from "../contracts/wms-packing/wms-packing.ts";

export type WmsPackingMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const WMS_PACKING_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_idempotency_key",
  "invalid_quantity",
  "invalid_reason",
  "invalid_weight",
  "invalid_dimensions",
  "invalid_uom",
  "invalid_uom_category",
  "invalid_seal",
  "invalid_qc_status",
  "invalid_package_type",
  "invalid_transition",
  "stale_version",
  "outbound_order_not_found",
  "outbound_order_not_confirmed",
  "warehouse_not_found",
  "packing_task_not_found",
  "package_not_found",
  "parent_package_not_found",
  "parent_package_confirmed",
  "cycle_rejected",
  "task_not_found",
  "wrong_order",
  "wrong_owner",
  "item_mismatch",
  "missing_lot",
  "lot_mismatch",
  "missing_serial",
  "serial_mismatch",
  "over_pack_rejected",
  "line_not_found",
  "exceeds_line_quantity",
  "confirmed_package_edit_rejected",
  "package_already_confirmed",
  "empty_package_rejected",
  "missing_measurement",
  "missing_qc",
  "qc_hold_unresolved",
  "missing_seal",
  "not_confirmed",
  "idempotency_key_conflict",
] as const;
type KnownWmsPackingMutationErrorCode = (typeof WMS_PACKING_KNOWN_MUTATION_ERROR_CODES)[number];
export type WmsPackingMutationErrorCode = KnownWmsPackingMutationErrorCode | "mutation_failed" | "invalid_response";

export class WmsPackingMutationError extends Error {
  readonly code: WmsPackingMutationErrorCode;

  constructor(code: WmsPackingMutationErrorCode, message: string) {
    super(message);
    this.name = "WmsPackingMutationError";
    this.code = code;
  }
}

function classifyError(message: string): WmsPackingMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (WMS_PACKING_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownWmsPackingMutationErrorCode)
    : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parsePackingTaskResponse(data: unknown, rpcName: string): WmsPackingTask {
  const row = firstRow(data);
  if (!row) {
    throw new WmsPackingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsPackingTask(row);
}

function parsePackageResponse(data: unknown, rpcName: string): WmsPackage {
  const row = firstRow(data);
  if (!row) {
    throw new WmsPackingMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseWmsPackage(row);
}

/** Idempotent on (tenant_id, idempotency_key), including under a genuine race, AND on unique (tenant_id, outbound_order_id) -- one packing task per order. */
export async function startWmsPackingTask(client: WmsPackingMutationRpcClient, input: StartWmsPackingTaskInput): Promise<WmsPackingTask> {
  const parsedInput = StartWmsPackingTaskInputSchema.parse(input);
  const { data, error } = await client.rpc("start_wms_packing_task", {
    p_outbound_order_id: parsedInput.outboundOrderId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackingTaskResponse(data, "start_wms_packing_task");
}

/** Idempotent on (tenant_id, idempotency_key), including under a genuine race. owner_account_id is always derived from the packing task's own outbound order, never caller-supplied. */
export async function createWmsPackage(client: WmsPackingMutationRpcClient, input: CreateWmsPackageInput): Promise<WmsPackage> {
  const parsedInput = CreateWmsPackageInputSchema.parse(input);
  const { data, error } = await client.rpc("create_wms_package", {
    p_packing_task_id: parsedInput.packingTaskId,
    p_parent_package_id: parsedInput.parentPackageId,
    p_package_type: parsedInput.packageType,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "create_wms_package");
}

/** Real, bounded ancestor-walk cycle rejection. Only permitted while both the package being moved and its proposed new parent are open. */
export async function reparentWmsPackage(client: WmsPackingMutationRpcClient, input: ReparentWmsPackageInput): Promise<WmsPackage> {
  const parsedInput = ReparentWmsPackageInputSchema.parse(input);
  const { data, error } = await client.rpc("reparent_wms_package", {
    p_package_id: parsedInput.packageId,
    p_new_parent_package_id: parsedInput.newParentPackageId,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "reparent_wms_package");
}

/** Locks the target pick task row before computing how much of it has already been packed across all packages -- the double-pack-prevention guard. Idempotent on (tenant_id, idempotency_key). */
export async function addWmsPackageLine(client: WmsPackingMutationRpcClient, input: AddWmsPackageLineInput): Promise<WmsPackage> {
  const parsedInput = AddWmsPackageLineInputSchema.parse(input);
  const { data, error } = await client.rpc("add_wms_package_line", {
    p_package_id: parsedInput.packageId,
    p_pick_task_id: parsedInput.pickTaskId,
    p_quantity: parsedInput.quantity,
    p_scanned_item_master_id: parsedInput.scannedItemMasterId,
    p_scanned_lot_number: parsedInput.scannedLotNumber,
    p_scanned_serial_number: parsedInput.scannedSerialNumber,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "add_wms_package_line");
}

/** Only ever callable pre-confirm. A real, non-empty reason is required for every removal. Idempotent on (tenant_id, idempotency_key). */
export async function removeWmsPackageLine(client: WmsPackingMutationRpcClient, input: RemoveWmsPackageLineInput): Promise<WmsPackage> {
  const parsedInput = RemoveWmsPackageLineInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_wms_package_line", {
    p_package_id: parsedInput.packageId,
    p_pick_task_id: parsedInput.pickTaskId,
    p_quantity: parsedInput.quantity,
    p_reason: parsedInput.reason,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "remove_wms_package_line");
}

/** Weight is mandatory (weight-category UOM); length/width/height/dimension_uom_code are optional but must be supplied together (length-category UOM) or not at all. */
export async function recordWmsPackageMeasurements(client: WmsPackingMutationRpcClient, input: RecordWmsPackageMeasurementsInput): Promise<WmsPackage> {
  const parsedInput = RecordWmsPackageMeasurementsInputSchema.parse(input);
  const { data, error } = await client.rpc("record_wms_package_measurements", {
    p_package_id: parsedInput.packageId,
    p_weight_value: parsedInput.weightValue,
    p_weight_uom_code: parsedInput.weightUomCode,
    p_length_value: parsedInput.lengthValue,
    p_width_value: parsedInput.widthValue,
    p_height_value: parsedInput.heightValue,
    p_dimension_uom_code: parsedInput.dimensionUomCode,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "record_wms_package_measurements");
}

/** Real, bounded pass/fail/hold outcome, never a configurable checklist engine. A fresh QC event always supersedes any prior override. */
export async function recordWmsPackageQc(client: WmsPackingMutationRpcClient, input: RecordWmsPackageQcInput): Promise<WmsPackage> {
  const parsedInput = RecordWmsPackageQcInputSchema.parse(input);
  const { data, error } = await client.rpc("record_wms_package_qc", {
    p_package_id: parsedInput.packageId,
    p_qc_status: parsedInput.qcStatus,
    p_qc_reason: parsedInput.qcReason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "record_wms_package_qc");
}

/** OPS:Override-gated (supervisor-only). Records a distinct, privileged qc_override_* evidence trail -- the original failed/held qc_status is never silently overwritten. */
export async function overrideWmsPackageQcHold(client: WmsPackingMutationRpcClient, input: OverrideWmsPackageQcHoldInput): Promise<WmsPackage> {
  const parsedInput = OverrideWmsPackageQcHoldInputSchema.parse(input);
  const { data, error } = await client.rpc("override_wms_package_qc_hold", {
    p_package_id: parsedInput.packageId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "override_wms_package_qc_hold");
}

/** Only ever callable pre-confirm. app.confirm_wms_package requires a real seal_number for any root package (parent_package_id is null). */
export async function recordWmsPackageSeal(client: WmsPackingMutationRpcClient, input: RecordWmsPackageSealInput): Promise<WmsPackage> {
  const parsedInput = RecordWmsPackageSealInputSchema.parse(input);
  const { data, error } = await client.rpc("record_wms_package_seal", {
    p_package_id: parsedInput.packageId,
    p_seal_number: parsedInput.sealNumber,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "record_wms_package_seal");
}

/** The "confirms once" step. Rejects empty_package_rejected/missing_measurement/missing_qc/qc_hold_unresolved/missing_seal. Idempotent on (tenant_id, idempotency_key). */
export async function confirmWmsPackage(client: WmsPackingMutationRpcClient, input: ConfirmWmsPackageInput): Promise<WmsPackage> {
  const parsedInput = ConfirmWmsPackageInputSchema.parse(input);
  const { data, error } = await client.rpc("confirm_wms_package", {
    p_package_id: parsedInput.packageId,
    p_idempotency_key: parsedInput.idempotencyKey,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "confirm_wms_package");
}

/** OPS:Override-gated (supervisor-only). The only path back from confirmed -- resets QC/seal, preserves packed line contents, records a full before/after audit event. */
export async function reopenWmsPackage(client: WmsPackingMutationRpcClient, input: ReopenWmsPackageInput): Promise<WmsPackage> {
  const parsedInput = ReopenWmsPackageInputSchema.parse(input);
  const { data, error } = await client.rpc("reopen_wms_package", {
    p_package_id: parsedInput.packageId,
    p_reason: parsedInput.reason,
    p_expected_version: parsedInput.expectedVersion,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new WmsPackingMutationError(classifyError(error.message), error.message);
  }
  return parsePackageResponse(data, "reopen_wms_package");
}
