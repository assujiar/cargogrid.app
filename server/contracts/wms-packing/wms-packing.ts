/**
 * WMS Packing contract (ATW-018, CG-S10-ATW-018, Prompt 237). Mirrors
 * supabase/migrations/20260730250000_create_advanced_tms_wms_packing.sql's
 * app.wms_packing_tasks/app.wms_packages/app.wms_package_lines/
 * app.wms_package_line_scans/app.wms_package_confirmations shapes and their
 * start-task/create-package/reparent/add-line/remove-line/measure/qc/qc-override/
 * seal/confirm/reopen/read RPCs.
 */

import { z } from "zod";

export const WMS_PACKAGE_STATUSES = ["open", "confirmed"] as const;
export const WmsPackageStatusSchema = z.enum(WMS_PACKAGE_STATUSES);
export type WmsPackageStatus = z.infer<typeof WmsPackageStatusSchema>;

export const WMS_PACKAGE_TYPES = ["carton", "box", "pallet", "crate", "container", "envelope", "other"] as const;
export const WmsPackageTypeSchema = z.enum(WMS_PACKAGE_TYPES);
export type WmsPackageType = z.infer<typeof WmsPackageTypeSchema>;

export const WMS_PACKAGE_QC_STATUSES = ["pending", "pass", "fail", "hold"] as const;
export const WmsPackageQcStatusSchema = z.enum(WMS_PACKAGE_QC_STATUSES);
export type WmsPackageQcStatus = z.infer<typeof WmsPackageQcStatusSchema>;

export const WmsPackingTaskSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  outboundOrderId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  packingTaskNumber: z.string(),
  idempotencyKey: z.string(),
  createdAt: z.string(),
});
export type WmsPackingTask = z.infer<typeof WmsPackingTaskSchema>;

export function parseWmsPackingTask(row: Record<string, unknown>): WmsPackingTask {
  return WmsPackingTaskSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    outboundOrderId: row.outbound_order_id,
    ownerAccountId: row.owner_account_id,
    packingTaskNumber: row.packing_task_number,
    idempotencyKey: row.idempotency_key,
    createdAt: row.created_at,
  });
}

export const WmsPackageSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  warehouseId: z.string().uuid(),
  packingTaskId: z.string().uuid(),
  outboundOrderId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  parentPackageId: z.string().uuid().nullable(),
  packageNumber: z.string(),
  packageType: WmsPackageTypeSchema,
  status: WmsPackageStatusSchema,
  weightValue: z.coerce.number().nullable(),
  weightUomCode: z.string().nullable(),
  lengthValue: z.coerce.number().nullable(),
  widthValue: z.coerce.number().nullable(),
  heightValue: z.coerce.number().nullable(),
  dimensionUomCode: z.string().nullable(),
  material: z.string().nullable(),
  qcStatus: WmsPackageQcStatusSchema,
  qcReason: z.string().nullable(),
  qcByAuthUserId: z.string().uuid().nullable(),
  qcByLabel: z.string().nullable(),
  qcAt: z.string().nullable(),
  qcOverrideReason: z.string().nullable(),
  qcOverrideByAuthUserId: z.string().uuid().nullable(),
  qcOverrideByLabel: z.string().nullable(),
  qcOverrideAt: z.string().nullable(),
  sealNumber: z.string().nullable(),
  sealedByAuthUserId: z.string().uuid().nullable(),
  sealedByLabel: z.string().nullable(),
  sealedAt: z.string().nullable(),
  lineCount: z.coerce.number().int(),
  totalPackedQuantity: z.coerce.number(),
  confirmedAt: z.string().nullable(),
  confirmedByAuthUserId: z.string().uuid().nullable(),
  confirmedByLabel: z.string().nullable(),
  reopenCount: z.coerce.number().int(),
  reopenedAt: z.string().nullable(),
  reopenedByAuthUserId: z.string().uuid().nullable(),
  reopenedByLabel: z.string().nullable(),
  reopenedReason: z.string().nullable(),
  idempotencyKey: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type WmsPackage = z.infer<typeof WmsPackageSchema>;

export function parseWmsPackage(row: Record<string, unknown>): WmsPackage {
  return WmsPackageSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    warehouseId: row.warehouse_id,
    packingTaskId: row.packing_task_id,
    outboundOrderId: row.outbound_order_id,
    ownerAccountId: row.owner_account_id,
    parentPackageId: row.parent_package_id ?? null,
    packageNumber: row.package_number,
    packageType: row.package_type,
    status: row.status,
    weightValue: row.weight_value ?? null,
    weightUomCode: row.weight_uom_code ?? null,
    lengthValue: row.length_value ?? null,
    widthValue: row.width_value ?? null,
    heightValue: row.height_value ?? null,
    dimensionUomCode: row.dimension_uom_code ?? null,
    material: row.material ?? null,
    qcStatus: row.qc_status,
    qcReason: row.qc_reason ?? null,
    qcByAuthUserId: row.qc_by_auth_user_id ?? null,
    qcByLabel: row.qc_by_label ?? null,
    qcAt: row.qc_at ?? null,
    qcOverrideReason: row.qc_override_reason ?? null,
    qcOverrideByAuthUserId: row.qc_override_by_auth_user_id ?? null,
    qcOverrideByLabel: row.qc_override_by_label ?? null,
    qcOverrideAt: row.qc_override_at ?? null,
    sealNumber: row.seal_number ?? null,
    sealedByAuthUserId: row.sealed_by_auth_user_id ?? null,
    sealedByLabel: row.sealed_by_label ?? null,
    sealedAt: row.sealed_at ?? null,
    lineCount: row.line_count,
    totalPackedQuantity: row.total_packed_quantity,
    confirmedAt: row.confirmed_at ?? null,
    confirmedByAuthUserId: row.confirmed_by_auth_user_id ?? null,
    confirmedByLabel: row.confirmed_by_label ?? null,
    reopenCount: row.reopen_count,
    reopenedAt: row.reopened_at ?? null,
    reopenedByAuthUserId: row.reopened_by_auth_user_id ?? null,
    reopenedByLabel: row.reopened_by_label ?? null,
    reopenedReason: row.reopened_reason ?? null,
    idempotencyKey: row.idempotency_key,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const WmsPackageLineSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  packageId: z.string().uuid(),
  pickTaskId: z.string().uuid(),
  ownerAccountId: z.string().uuid(),
  itemMasterId: z.string().uuid(),
  uomCode: z.string(),
  lotNumber: z.string().nullable(),
  serialNumber: z.string().nullable(),
  expiryDate: z.string().nullable(),
  quantity: z.coerce.number(),
  firstAddedAt: z.string(),
  firstAddedByAuthUserId: z.string().uuid().nullable(),
  firstAddedByLabel: z.string().nullable(),
});
export type WmsPackageLine = z.infer<typeof WmsPackageLineSchema>;

export function parseWmsPackageLine(row: Record<string, unknown>): WmsPackageLine {
  return WmsPackageLineSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    packageId: row.package_id,
    pickTaskId: row.pick_task_id,
    ownerAccountId: row.owner_account_id,
    itemMasterId: row.item_master_id,
    uomCode: row.uom_code,
    lotNumber: row.lot_number ?? null,
    serialNumber: row.serial_number ?? null,
    expiryDate: row.expiry_date ?? null,
    quantity: row.quantity,
    firstAddedAt: row.first_added_at,
    firstAddedByAuthUserId: row.first_added_by_auth_user_id ?? null,
    firstAddedByLabel: row.first_added_by_label ?? null,
  });
}

export const WmsPackageLineScanSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  packageId: z.string().uuid(),
  pickTaskId: z.string().uuid(),
  eventType: z.enum(["add", "remove"]),
  quantity: z.coerce.number(),
  scannedItemMasterId: z.string().uuid().nullable(),
  scannedLotNumber: z.string().nullable(),
  scannedSerialNumber: z.string().nullable(),
  reason: z.string().nullable(),
  idempotencyKey: z.string(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type WmsPackageLineScan = z.infer<typeof WmsPackageLineScanSchema>;

export function parseWmsPackageLineScan(row: Record<string, unknown>): WmsPackageLineScan {
  return WmsPackageLineScanSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    packageId: row.package_id,
    pickTaskId: row.pick_task_id,
    eventType: row.event_type,
    quantity: row.quantity,
    scannedItemMasterId: row.scanned_item_master_id ?? null,
    scannedLotNumber: row.scanned_lot_number ?? null,
    scannedSerialNumber: row.scanned_serial_number ?? null,
    reason: row.reason ?? null,
    idempotencyKey: row.idempotency_key,
    actorAuthUserId: row.actor_auth_user_id ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

export const WmsPackageConfirmationSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  packageId: z.string().uuid(),
  idempotencyKey: z.string(),
  lineCountSnapshot: z.coerce.number().int(),
  totalQuantitySnapshot: z.coerce.number(),
  confirmedByAuthUserId: z.string().uuid().nullable(),
  confirmedByLabel: z.string().nullable(),
  confirmedAt: z.string(),
});
export type WmsPackageConfirmation = z.infer<typeof WmsPackageConfirmationSchema>;

export function parseWmsPackageConfirmation(row: Record<string, unknown>): WmsPackageConfirmation {
  return WmsPackageConfirmationSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    packageId: row.package_id,
    idempotencyKey: row.idempotency_key,
    lineCountSnapshot: row.line_count_snapshot,
    totalQuantitySnapshot: row.total_quantity_snapshot,
    confirmedByAuthUserId: row.confirmed_by_auth_user_id ?? null,
    confirmedByLabel: row.confirmed_by_label ?? null,
    confirmedAt: row.confirmed_at,
  });
}

// --- Mutation input schemas ---

export const StartWmsPackingTaskInputSchema = z.object({
  outboundOrderId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type StartWmsPackingTaskInput = z.input<typeof StartWmsPackingTaskInputSchema>;

export const CreateWmsPackageInputSchema = z.object({
  packingTaskId: z.string().uuid(),
  parentPackageId: z.string().uuid().nullable(),
  packageType: WmsPackageTypeSchema,
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateWmsPackageInput = z.input<typeof CreateWmsPackageInputSchema>;

export const ReparentWmsPackageInputSchema = z.object({
  packageId: z.string().uuid(),
  newParentPackageId: z.string().uuid().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReparentWmsPackageInput = z.input<typeof ReparentWmsPackageInputSchema>;

export const AddWmsPackageLineInputSchema = z.object({
  packageId: z.string().uuid(),
  pickTaskId: z.string().uuid(),
  quantity: z.number().positive(),
  scannedItemMasterId: z.string().uuid(),
  scannedLotNumber: z.string().nullable(),
  scannedSerialNumber: z.string().nullable(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddWmsPackageLineInput = z.input<typeof AddWmsPackageLineInputSchema>;

export const RemoveWmsPackageLineInputSchema = z.object({
  packageId: z.string().uuid(),
  pickTaskId: z.string().uuid(),
  quantity: z.number().positive(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveWmsPackageLineInput = z.input<typeof RemoveWmsPackageLineInputSchema>;

export const RecordWmsPackageMeasurementsInputSchema = z.object({
  packageId: z.string().uuid(),
  weightValue: z.number().positive(),
  weightUomCode: z.string().min(1),
  lengthValue: z.number().positive().nullable(),
  widthValue: z.number().positive().nullable(),
  heightValue: z.number().positive().nullable(),
  dimensionUomCode: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordWmsPackageMeasurementsInput = z.input<typeof RecordWmsPackageMeasurementsInputSchema>;

export const RecordWmsPackageQcInputSchema = z.object({
  packageId: z.string().uuid(),
  qcStatus: z.enum(["pass", "fail", "hold"]),
  qcReason: z.string().nullable(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordWmsPackageQcInput = z.input<typeof RecordWmsPackageQcInputSchema>;

export const OverrideWmsPackageQcHoldInputSchema = z.object({
  packageId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type OverrideWmsPackageQcHoldInput = z.input<typeof OverrideWmsPackageQcHoldInputSchema>;

export const RecordWmsPackageSealInputSchema = z.object({
  packageId: z.string().uuid(),
  sealNumber: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordWmsPackageSealInput = z.input<typeof RecordWmsPackageSealInputSchema>;

export const ConfirmWmsPackageInputSchema = z.object({
  packageId: z.string().uuid(),
  idempotencyKey: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ConfirmWmsPackageInput = z.input<typeof ConfirmWmsPackageInputSchema>;

export const ReopenWmsPackageInputSchema = z.object({
  packageId: z.string().uuid(),
  reason: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReopenWmsPackageInput = z.input<typeof ReopenWmsPackageInputSchema>;
