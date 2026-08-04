import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  startWmsPackingTask,
  createWmsPackage,
  reparentWmsPackage,
  addWmsPackageLine,
  removeWmsPackageLine,
  recordWmsPackageMeasurements,
  recordWmsPackageQc,
  overrideWmsPackageQcHold,
  recordWmsPackageSeal,
  confirmWmsPackage,
  reopenWmsPackage,
  WmsPackingMutationError,
  type WmsPackingMutationRpcClient,
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
const SUPERVISOR_ID = "b23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsPackingMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsPackingMutationRpcClient;
  return { client, calls };
}

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

describe("startWmsPackingTask", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKING_TASK_ROW], error: null });
    const task = await startWmsPackingTask(client, { outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(task.outboundOrderId, OUTBOUND_ORDER_ID);
    assert.equal(calls[0]?.fn, "start_wms_packing_task");
  });

  test("classifies outbound_order_not_confirmed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "outbound_order_not_confirmed: x is draft -- only confirmed outbound demand may be packed against" } });
    await assert.rejects(
      () => startWmsPackingTask(client, { outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "idem-2", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "outbound_order_not_confirmed",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () => startWmsPackingTask(client, { outboundOrderId: OUTBOUND_ORDER_ID, idempotencyKey: "idem-3", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "mutation_failed",
    );
  });
});

describe("createWmsPackage", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKAGE_ROW], error: null });
    const pkg = await createWmsPackage(client, { packingTaskId: PACKING_TASK_ID, parentPackageId: null, packageType: "carton", idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "packer" });
    assert.equal(pkg.packingTaskId, PACKING_TASK_ID);
    assert.equal(calls[0]?.fn, "create_wms_package");
    assert.equal(calls[0]?.args.p_parent_package_id, null);
  });

  test("classifies parent_package_confirmed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "parent_package_confirmed: x has already been confirmed -- reopen it before nesting a new child under it" } });
    await assert.rejects(
      () => createWmsPackage(client, { packingTaskId: PACKING_TASK_ID, parentPackageId: PACKAGE_ID, packageType: "box", idempotencyKey: "idem-2", actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "parent_package_confirmed",
    );
  });
});

describe("reparentWmsPackage", () => {
  test("classifies cycle_rejected", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "cycle_rejected: reparenting package x under y would create a cycle" } });
    await assert.rejects(
      () => reparentWmsPackage(client, { packageId: PACKAGE_ID, newParentPackageId: PICK_TASK_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "cycle_rejected",
    );
  });

  test("sends a null newParentPackageId through unchanged (detach to root)", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKAGE_ROW], error: null });
    await reparentWmsPackage(client, { packageId: PACKAGE_ID, newParentPackageId: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" });
    assert.equal(calls[0]?.args.p_new_parent_package_id, null);
  });
});

describe("addWmsPackageLine", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PACKAGE_ROW, line_count: 1, total_packed_quantity: "10" }], error: null });
    const pkg = await addWmsPackageLine(client, {
      packageId: PACKAGE_ID,
      pickTaskId: PICK_TASK_ID,
      quantity: 10,
      scannedItemMasterId: ITEM_ID,
      scannedLotNumber: null,
      scannedSerialNumber: null,
      idempotencyKey: "idem-add-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "packer",
    });
    assert.equal(pkg.lineCount, 1);
    assert.equal(calls[0]?.fn, "add_wms_package_line");
    assert.equal(calls[0]?.args.p_quantity, 10);
  });

  test("classifies over_pack_rejected", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "over_pack_rejected: 5 of 10 picked units remain unpacked for pick task x, requested 8" } });
    await assert.rejects(
      () =>
        addWmsPackageLine(client, {
          packageId: PACKAGE_ID,
          pickTaskId: PICK_TASK_ID,
          quantity: 8,
          scannedItemMasterId: ITEM_ID,
          scannedLotNumber: null,
          scannedSerialNumber: null,
          idempotencyKey: "idem-add-2",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "packer",
        }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "over_pack_rejected",
    );
  });

  test("classifies wrong_owner", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "wrong_owner: pick task x belongs to owner account y, not this package's own owner account z" } });
    await assert.rejects(
      () =>
        addWmsPackageLine(client, {
          packageId: PACKAGE_ID,
          pickTaskId: PICK_TASK_ID,
          quantity: 5,
          scannedItemMasterId: ITEM_ID,
          scannedLotNumber: null,
          scannedSerialNumber: null,
          idempotencyKey: "idem-add-3",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "packer",
        }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "wrong_owner",
    );
  });

  test("classifies item_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "item_mismatch: scanned item x does not match pick task y's own item z" } });
    await assert.rejects(
      () =>
        addWmsPackageLine(client, {
          packageId: PACKAGE_ID,
          pickTaskId: PICK_TASK_ID,
          quantity: 5,
          scannedItemMasterId: ITEM_ID,
          scannedLotNumber: null,
          scannedSerialNumber: null,
          idempotencyKey: "idem-add-4",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "packer",
        }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "item_mismatch",
    );
  });
});

describe("removeWmsPackageLine", () => {
  test("classifies exceeds_line_quantity", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "exceeds_line_quantity: package x only has 3 of pick task y packed, cannot remove 5" } });
    await assert.rejects(
      () => removeWmsPackageLine(client, { packageId: PACKAGE_ID, pickTaskId: PICK_TASK_ID, quantity: 5, reason: "damaged", idempotencyKey: "idem-rm-1", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "exceeds_line_quantity",
    );
  });

  test("sends a real reason through", async () => {
    const { client, calls } = fakeRpcClient({ data: [PACKAGE_ROW], error: null });
    await removeWmsPackageLine(client, { packageId: PACKAGE_ID, pickTaskId: PICK_TASK_ID, quantity: 2, reason: "duplicate scan", idempotencyKey: "idem-rm-2", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" });
    assert.equal(calls[0]?.args.p_reason, "duplicate scan");
  });
});

describe("recordWmsPackageMeasurements", () => {
  test("classifies invalid_uom_category", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_uom_category: PCS is a count UOM, weight is required for weight_uom_code" } });
    await assert.rejects(
      () =>
        recordWmsPackageMeasurements(client, {
          packageId: PACKAGE_ID,
          weightValue: 5,
          weightUomCode: "PCS",
          lengthValue: null,
          widthValue: null,
          heightValue: null,
          dimensionUomCode: null,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "packer",
        }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "invalid_uom_category",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PACKAGE_ROW, weight_value: "12.5", weight_uom_code: "KG" }], error: null });
    const pkg = await recordWmsPackageMeasurements(client, {
      packageId: PACKAGE_ID,
      weightValue: 12.5,
      weightUomCode: "KG",
      lengthValue: 30,
      widthValue: 20,
      heightValue: 15,
      dimensionUomCode: "CM",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "packer",
    });
    assert.equal(pkg.weightValue, 12.5);
    assert.equal(calls[0]?.args.p_length_value, 30);
  });
});

describe("recordWmsPackageQc", () => {
  test("classifies invalid_reason for a fail with no reason (server-side rejection surfaced)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_reason: a non-empty reason is required for a fail QC outcome" } });
    await assert.rejects(
      () => recordWmsPackageQc(client, { packageId: PACKAGE_ID, qcStatus: "fail", qcReason: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "invalid_reason",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PACKAGE_ROW, qc_status: "pass" }], error: null });
    const pkg = await recordWmsPackageQc(client, { packageId: PACKAGE_ID, qcStatus: "pass", qcReason: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" });
    assert.equal(pkg.qcStatus, "pass");
    assert.equal(calls[0]?.fn, "record_wms_package_qc");
  });
});

describe("overrideWmsPackageQcHold", () => {
  test("classifies insufficient_authority for a non-supervisor caller", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:Override (no matching grant) for tenant y" } });
    await assert.rejects(
      () => overrideWmsPackageQcHold(client, { packageId: PACKAGE_ID, reason: "customer accepted risk", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "insufficient_authority",
    );
  });

  test("classifies invalid_transition when there is nothing to override", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: package x QC status is pending -- only a failed or held package may be overridden" } });
    await assert.rejects(
      () => overrideWmsPackageQcHold(client, { packageId: PACKAGE_ID, reason: "n/a", expectedVersion: 1, actorAuthUserId: SUPERVISOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "invalid_transition",
    );
  });
});

describe("recordWmsPackageSeal", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PACKAGE_ROW, seal_number: "SEAL-0001" }], error: null });
    const pkg = await recordWmsPackageSeal(client, { packageId: PACKAGE_ID, sealNumber: "SEAL-0001", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" });
    assert.equal(pkg.sealNumber, "SEAL-0001");
    assert.equal(calls[0]?.fn, "record_wms_package_seal");
  });
});

describe("confirmWmsPackage", () => {
  test("classifies empty_package_rejected", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "empty_package_rejected: package x has no packed contents" } });
    await assert.rejects(
      () => confirmWmsPackage(client, { packageId: PACKAGE_ID, idempotencyKey: "idem-confirm-1", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "empty_package_rejected",
    );
  });

  test("classifies missing_seal", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "missing_seal: root package x has no recorded seal" } });
    await assert.rejects(
      () => confirmWmsPackage(client, { packageId: PACKAGE_ID, idempotencyKey: "idem-confirm-2", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "missing_seal",
    );
  });

  test("classifies qc_hold_unresolved", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "qc_hold_unresolved: package x QC outcome is hold -- resolve or override before confirming" } });
    await assert.rejects(
      () => confirmWmsPackage(client, { packageId: PACKAGE_ID, idempotencyKey: "idem-confirm-3", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "qc_hold_unresolved",
    );
  });

  test("sends the mapped RPC args and parses the response row on success", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PACKAGE_ROW, status: "confirmed", confirmed_at: "2026-08-03T01:00:00.000Z", confirmed_by_auth_user_id: ACTOR_ID }], error: null });
    const pkg = await confirmWmsPackage(client, { packageId: PACKAGE_ID, idempotencyKey: "idem-confirm-4", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "packer" });
    assert.equal(pkg.status, "confirmed");
    assert.equal(calls[0]?.fn, "confirm_wms_package");
  });
});

describe("reopenWmsPackage", () => {
  test("classifies not_confirmed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "not_confirmed: package x is open -- only a confirmed package may be reopened" } });
    await assert.rejects(
      () => reopenWmsPackage(client, { packageId: PACKAGE_ID, reason: "wrong contents", expectedVersion: 1, actorAuthUserId: SUPERVISOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof WmsPackingMutationError && err.code === "not_confirmed",
    );
  });

  test("sends the mapped RPC args and parses the response row on success", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PACKAGE_ROW, status: "open", reopen_count: 1, reopened_reason: "wrong contents" }], error: null });
    const pkg = await reopenWmsPackage(client, { packageId: PACKAGE_ID, reason: "wrong contents", expectedVersion: 2, actorAuthUserId: SUPERVISOR_ID, actorLabel: "supervisor" });
    assert.equal(pkg.status, "open");
    assert.equal(pkg.reopenCount, 1);
    assert.equal(calls[0]?.fn, "reopen_wms_package");
  });
});
