import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWmsPackingTask,
  parseWmsPackage,
  parseWmsPackageLine,
  parseWmsPackageLineScan,
  parseWmsPackageConfirmation,
  StartWmsPackingTaskInputSchema,
  CreateWmsPackageInputSchema,
  AddWmsPackageLineInputSchema,
  RecordWmsPackageMeasurementsInputSchema,
  RecordWmsPackageQcInputSchema,
  ConfirmWmsPackageInputSchema,
} from "./wms-packing.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const PACKING_TASK_ID = "523e4567-e89b-12d3-a456-426614174000";
const PACKAGE_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const PICK_TASK_ID = "a23e4567-e89b-12d3-a456-426614174000";
const LINE_ID = "b23e4567-e89b-12d3-a456-426614174000";
const SCAN_ID = "c23e4567-e89b-12d3-a456-426614174000";
const CONFIRMATION_ID = "d23e4567-e89b-12d3-a456-426614174000";

const PACKING_TASK_ROW = {
  id: PACKING_TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  owner_account_id: OWNER_ID,
  packing_task_number: "WMSPACK-2026-000001",
  idempotency_key: "idem-packtask-1",
  created_at: "2026-08-03T00:00:00.000Z",
};

const PACKAGE_ROW = {
  id: PACKAGE_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  packing_task_id: PACKING_TASK_ID,
  outbound_order_id: OUTBOUND_ORDER_ID,
  owner_account_id: OWNER_ID,
  parent_package_id: null,
  package_number: "PKG-2026-0000001",
  package_type: "carton",
  status: "open",
  weight_value: null,
  weight_uom_code: null,
  length_value: null,
  width_value: null,
  height_value: null,
  dimension_uom_code: null,
  material: null,
  qc_status: "pending",
  qc_reason: null,
  qc_by_auth_user_id: null,
  qc_by_label: null,
  qc_at: null,
  qc_override_reason: null,
  qc_override_by_auth_user_id: null,
  qc_override_by_label: null,
  qc_override_at: null,
  seal_number: null,
  sealed_by_auth_user_id: null,
  sealed_by_label: null,
  sealed_at: null,
  line_count: 0,
  total_packed_quantity: "0",
  confirmed_at: null,
  confirmed_by_auth_user_id: null,
  confirmed_by_label: null,
  reopen_count: 0,
  reopened_at: null,
  reopened_by_auth_user_id: null,
  reopened_by_label: null,
  reopened_reason: null,
  idempotency_key: "idem-pkg-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("parseWmsPackingTask", () => {
  test("maps snake_case columns to camelCase fields", () => {
    const task = parseWmsPackingTask(PACKING_TASK_ROW);
    assert.equal(task.outboundOrderId, OUTBOUND_ORDER_ID);
    assert.equal(task.packingTaskNumber, "WMSPACK-2026-000001");
  });
});

describe("parseWmsPackage", () => {
  test("maps snake_case columns to camelCase fields, coercing numeric strings", () => {
    const pkg = parseWmsPackage(PACKAGE_ROW);
    assert.equal(pkg.status, "open");
    assert.equal(pkg.totalPackedQuantity, 0);
    assert.equal(pkg.parentPackageId, null);
  });

  test("parses a confirmed, sealed, QC-passed root package", () => {
    const pkg = parseWmsPackage({
      ...PACKAGE_ROW,
      status: "confirmed",
      weight_value: "12.5",
      weight_uom_code: "KG",
      qc_status: "pass",
      qc_at: "2026-08-03T01:00:00.000Z",
      seal_number: "SEAL-0001",
      sealed_at: "2026-08-03T01:05:00.000Z",
      line_count: 2,
      total_packed_quantity: "18",
      confirmed_at: "2026-08-03T01:10:00.000Z",
      confirmed_by_auth_user_id: ACTOR_ID,
    });
    assert.equal(pkg.status, "confirmed");
    assert.equal(pkg.weightValue, 12.5);
    assert.equal(pkg.lineCount, 2);
    assert.equal(pkg.totalPackedQuantity, 18);
  });
});

describe("parseWmsPackageLine", () => {
  test("maps snake_case columns to camelCase fields", () => {
    const line = parseWmsPackageLine({
      id: LINE_ID,
      tenant_id: TENANT_ID,
      package_id: PACKAGE_ID,
      pick_task_id: PICK_TASK_ID,
      owner_account_id: OWNER_ID,
      item_master_id: ITEM_ID,
      uom_code: "PCS",
      lot_number: null,
      serial_number: null,
      expiry_date: null,
      quantity: "10",
      first_added_at: "2026-08-03T00:00:00.000Z",
      first_added_by_auth_user_id: ACTOR_ID,
      first_added_by_label: "packer",
    });
    assert.equal(line.quantity, 10);
    assert.equal(line.pickTaskId, PICK_TASK_ID);
  });
});

describe("parseWmsPackageLineScan", () => {
  test("maps an add event", () => {
    const scan = parseWmsPackageLineScan({
      id: SCAN_ID,
      tenant_id: TENANT_ID,
      package_id: PACKAGE_ID,
      pick_task_id: PICK_TASK_ID,
      event_type: "add",
      quantity: "10",
      scanned_item_master_id: ITEM_ID,
      scanned_lot_number: null,
      scanned_serial_number: null,
      reason: null,
      idempotency_key: "idem-scan-1",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "packer",
      occurred_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(scan.eventType, "add");
    assert.equal(scan.quantity, 10);
  });
});

describe("parseWmsPackageConfirmation", () => {
  test("maps snake_case columns to camelCase fields", () => {
    const confirmation = parseWmsPackageConfirmation({
      id: CONFIRMATION_ID,
      tenant_id: TENANT_ID,
      package_id: PACKAGE_ID,
      idempotency_key: "idem-confirm-1",
      line_count_snapshot: 2,
      total_quantity_snapshot: "18",
      confirmed_by_auth_user_id: ACTOR_ID,
      confirmed_by_label: "packer",
      confirmed_at: "2026-08-03T01:10:00.000Z",
    });
    assert.equal(confirmation.lineCountSnapshot, 2);
    assert.equal(confirmation.totalQuantitySnapshot, 18);
  });
});

describe("input schemas", () => {
  test("StartWmsPackingTaskInputSchema requires a non-empty idempotency key", () => {
    assert.throws(() =>
      StartWmsPackingTaskInputSchema.parse({ outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
    const parsed = StartWmsPackingTaskInputSchema.parse({ outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(parsed.outboundOrderId, OUTBOUND_ORDER_ID);
  });

  test("CreateWmsPackageInputSchema rejects an unrecognized package type", () => {
    assert.throws(() =>
      CreateWmsPackageInputSchema.parse({
        packingTaskId: PACKING_TASK_ID,
        parentPackageId: null,
        packageType: "spaceship",
        idempotencyKey: "idem-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "packer",
      }),
    );
  });

  test("AddWmsPackageLineInputSchema requires a positive quantity", () => {
    assert.throws(() =>
      AddWmsPackageLineInputSchema.parse({
        packageId: PACKAGE_ID,
        pickTaskId: PICK_TASK_ID,
        quantity: 0,
        scannedItemMasterId: ITEM_ID,
        scannedLotNumber: null,
        scannedSerialNumber: null,
        idempotencyKey: "idem-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "packer",
      }),
    );
  });

  test("RecordWmsPackageMeasurementsInputSchema requires a positive weight", () => {
    assert.throws(() =>
      RecordWmsPackageMeasurementsInputSchema.parse({
        packageId: PACKAGE_ID,
        weightValue: -1,
        weightUomCode: "KG",
        lengthValue: null,
        widthValue: null,
        heightValue: null,
        dimensionUomCode: null,
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "packer",
      }),
    );
  });

  test("RecordWmsPackageQcInputSchema rejects an unrecognized qc status", () => {
    assert.throws(() =>
      RecordWmsPackageQcInputSchema.parse({
        packageId: PACKAGE_ID,
        qcStatus: "maybe",
        qcReason: null,
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "packer",
      }),
    );
  });

  test("ConfirmWmsPackageInputSchema requires a non-empty idempotency key", () => {
    assert.throws(() =>
      ConfirmWmsPackageInputSchema.parse({ packageId: PACKAGE_ID, idempotencyKey: "", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
    );
  });
});
