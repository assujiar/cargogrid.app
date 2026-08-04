import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createWmsPickWave,
  generateWmsPickTask,
  claimWmsPickTask,
  confirmWmsPickTask,
  recordWmsPickTaskShort,
  markWmsPickTaskException,
  reassignWmsPickTask,
  cancelWmsPickTask,
  approveWmsPickSubstitution,
  WmsPickingMutationError,
  type WmsPickingMutationRpcClient,
} from "./wms-picking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OUTBOUND_LINE_ID = "523e4567-e89b-12d3-a456-426614174000";
const TASK_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "a23e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "b23e4567-e89b-12d3-a456-426614174000";
const SUPERVISOR_ID = "c23e4567-e89b-12d3-a456-426614174000";
const WAVE_ID = "d23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsPickingMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsPickingMutationRpcClient;
  return { client, calls };
}

const WAVE_ROW = {
  id: WAVE_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  wave_number: "WMSWAVE-2026-000001",
  idempotency_key: "idem-wave-1",
  created_at: "2026-08-03T00:00:00.000Z",
};

const TASK_ROW = {
  id: TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: "423e4567-e89b-12d3-a456-426614174000",
  outbound_order_line_id: OUTBOUND_LINE_ID,
  wave_id: null,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  uom_code: "PCS",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  source_location_id: LOCATION_ID,
  lot_number: null,
  serial_number: null,
  expiry_date: null,
  reservation_id: RESERVATION_ID,
  task_quantity: "50",
  picked_quantity: "0",
  short_quantity: "0",
  remaining_quantity: "50",
  suggested_destination_location_id: LOCATION_ID,
  suggested_destination_reason: "auto_suggested_first_eligible_staging",
  actual_destination_location_id: null,
  status: "unclaimed",
  claimed_by_auth_user_id: null,
  claimed_by_label: null,
  claimed_at: null,
  exception_reason: null,
  substituted_from_item_master_id: null,
  idempotency_key: "idem-task-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("createWmsPickWave", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [WAVE_ROW], error: null });
    const wave = await createWmsPickWave(client, { tenantId: TENANT_ID, warehouseId: WAREHOUSE_ID, idempotencyKey: "idem-wave-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(wave.waveNumber, "WMSWAVE-2026-000001");
    assert.equal(calls[0]?.fn, "create_wms_pick_wave");
  });
});

describe("generateWmsPickTask", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TASK_ROW], error: null });
    const task = await generateWmsPickTask(client, {
      outboundOrderLineId: OUTBOUND_LINE_ID,
      quantity: 50,
      waveId: null,
      locationId: null,
      lotNumber: null,
      serialNumber: null,
      suggestedDestinationLocationId: null,
      idempotencyKey: "idem-task-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(task.outboundOrderLineId, OUTBOUND_LINE_ID);
    assert.equal(calls[0]?.fn, "generate_wms_pick_task");
    assert.equal(calls[0]?.args.p_location_id, null);
  });

  test("classifies insufficient_remaining_quantity", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_remaining_quantity: 0 of 10 requested units remain unallocated for outbound order line x, requested 10" } });
    await assert.rejects(
      () =>
        generateWmsPickTask(client, {
          outboundOrderLineId: OUTBOUND_LINE_ID,
          quantity: 10,
          waveId: null,
          locationId: null,
          lotNumber: null,
          serialNumber: null,
          suggestedDestinationLocationId: null,
          idempotencyKey: "idem-task-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "insufficient_remaining_quantity",
    );
  });

  test("classifies no_eligible_pick_location", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "no_eligible_pick_location: no eligible candidate found for item x under warehouse y" } });
    await assert.rejects(
      () =>
        generateWmsPickTask(client, {
          outboundOrderLineId: OUTBOUND_LINE_ID,
          quantity: 10,
          waveId: null,
          locationId: null,
          lotNumber: null,
          serialNumber: null,
          suggestedDestinationLocationId: null,
          idempotencyKey: "idem-task-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "no_eligible_pick_location",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        generateWmsPickTask(client, {
          outboundOrderLineId: OUTBOUND_LINE_ID,
          quantity: 10,
          waveId: null,
          locationId: null,
          lotNumber: null,
          serialNumber: null,
          suggestedDestinationLocationId: null,
          idempotencyKey: "idem-task-4",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "mutation_failed",
    );
  });
});

describe("claimWmsPickTask", () => {
  test("classifies task_already_claimed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "task_already_claimed: task x is claimed (claimed_by=other-picker) -- only an unclaimed task may be claimed" } });
    await assert.rejects(
      () => claimWmsPickTask(client, { taskId: TASK_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "picker" }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "task_already_claimed",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "claimed", claimed_by_auth_user_id: ACTOR_ID, claimed_by_label: "picker", claimed_at: "2026-08-03T00:00:00.000Z" }], error: null });
    const task = await claimWmsPickTask(client, { taskId: TASK_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "picker" });
    assert.equal(task.status, "claimed");
    assert.equal(calls[0]?.fn, "claim_wms_pick_task");
  });
});

describe("confirmWmsPickTask", () => {
  test("classifies not_task_claimant", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "not_task_claimant: identity x is not the assigned claimant of task y" } });
    await assert.rejects(
      () =>
        confirmWmsPickTask(client, {
          taskId: TASK_ID,
          quantity: 50,
          scannedLocationId: LOCATION_ID,
          scannedItemMasterId: ITEM_ID,
          scannedLotNumber: null,
          scannedSerialNumber: null,
          actualDestinationLocationId: LOCATION_ID,
          idempotencyKey: "idem-confirm-1",
          expectedVersion: 2,
          actorAuthUserId: SUPERVISOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "not_task_claimant",
    );
  });

  test("classifies exceeds_remaining_quantity (over-pick hard rejection)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "exceeds_remaining_quantity: task x has 10 remaining but 20 was requested" } });
    await assert.rejects(
      () =>
        confirmWmsPickTask(client, {
          taskId: TASK_ID,
          quantity: 20,
          scannedLocationId: LOCATION_ID,
          scannedItemMasterId: ITEM_ID,
          scannedLotNumber: null,
          scannedSerialNumber: null,
          actualDestinationLocationId: LOCATION_ID,
          idempotencyKey: "idem-confirm-2",
          expectedVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "picker",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "exceeds_remaining_quantity",
    );
  });

  test("classifies location_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "location_mismatch: scanned location x does not match task y's own source location z" } });
    await assert.rejects(
      () =>
        confirmWmsPickTask(client, {
          taskId: TASK_ID,
          quantity: 5,
          scannedLocationId: LOCATION_ID,
          scannedItemMasterId: ITEM_ID,
          scannedLotNumber: null,
          scannedSerialNumber: null,
          actualDestinationLocationId: LOCATION_ID,
          idempotencyKey: "idem-confirm-3",
          expectedVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "picker",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "location_mismatch",
    );
  });

  test("classifies destination_full", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "destination_full: destination x has 5 of 5 capacity occupied -- 1 more would exceed it" } });
    await assert.rejects(
      () =>
        confirmWmsPickTask(client, {
          taskId: TASK_ID,
          quantity: 1,
          scannedLocationId: LOCATION_ID,
          scannedItemMasterId: ITEM_ID,
          scannedLotNumber: null,
          scannedSerialNumber: null,
          actualDestinationLocationId: LOCATION_ID,
          idempotencyKey: "idem-confirm-4",
          expectedVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "picker",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "destination_full",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "picked", picked_quantity: "50", remaining_quantity: "0", actual_destination_location_id: LOCATION_ID }], error: null });
    const task = await confirmWmsPickTask(client, {
      taskId: TASK_ID,
      quantity: 50,
      scannedLocationId: LOCATION_ID,
      scannedItemMasterId: ITEM_ID,
      scannedLotNumber: null,
      scannedSerialNumber: null,
      actualDestinationLocationId: LOCATION_ID,
      idempotencyKey: "idem-confirm-5",
      expectedVersion: 2,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "picker",
    });
    assert.equal(task.status, "picked");
    assert.equal(calls[0]?.fn, "confirm_wms_pick_task");
    assert.equal(calls[0]?.args.p_quantity, 50);
  });
});

describe("recordWmsPickTaskShort", () => {
  test("classifies exceeds_remaining_quantity", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "exceeds_remaining_quantity: task x has 10 remaining but a short of 20 was requested" } });
    await assert.rejects(
      () =>
        recordWmsPickTaskShort(client, {
          taskId: TASK_ID,
          shortQuantity: 20,
          reason: "shelf empty",
          idempotencyKey: "idem-short-1",
          expectedVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "picker",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "exceeds_remaining_quantity",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "partial", short_quantity: "5", remaining_quantity: "45" }], error: null });
    const task = await recordWmsPickTaskShort(client, {
      taskId: TASK_ID,
      shortQuantity: 5,
      reason: "shelf empty",
      idempotencyKey: "idem-short-2",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "picker",
    });
    assert.equal(task.shortQuantity, 5);
    assert.equal(calls[0]?.fn, "record_wms_pick_task_short");
    assert.equal(calls[0]?.args.p_reason, "shelf empty");
  });
});

describe("markWmsPickTaskException", () => {
  test("classifies invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: task x is unclaimed -- only a claimed or partially-picked task may be marked exception" } });
    await assert.rejects(
      () => markWmsPickTaskException(client, { taskId: TASK_ID, reason: "shelf blocked", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "picker" }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "invalid_transition",
    );
  });
});

describe("reassignWmsPickTask", () => {
  test("sends a null newClaimantAuthUserId through unchanged (release path)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "unclaimed" }], error: null });
    const task = await reassignWmsPickTask(client, {
      taskId: TASK_ID,
      newClaimantAuthUserId: null,
      newClaimantLabel: null,
      reason: "picker went home sick",
      expectedVersion: 2,
      actorAuthUserId: SUPERVISOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(task.status, "unclaimed");
    assert.equal(calls[0]?.args.p_new_claimant_auth_user_id, null);
  });

  test("classifies insufficient_authority for a non-supervisor caller", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:Override (no matching grant) for tenant y" } });
    await assert.rejects(
      () =>
        reassignWmsPickTask(client, {
          taskId: TASK_ID,
          newClaimantAuthUserId: null,
          newClaimantLabel: null,
          reason: "attempted reassign",
          expectedVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "picker",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("cancelWmsPickTask", () => {
  test("classifies has_pick_progress", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "has_pick_progress: task x has already picked 10 and shorted 0 unit(s) -- a task with real progress may never be cancelled, only completed or reassigned" } });
    await assert.rejects(
      () => cancelWmsPickTask(client, { taskId: TASK_ID, reason: "duplicate task", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "has_pick_progress",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "cancelled" }], error: null });
    const task = await cancelWmsPickTask(client, { taskId: TASK_ID, reason: "duplicate task", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(task.status, "cancelled");
    assert.equal(calls[0]?.fn, "cancel_wms_pick_task");
  });
});

describe("approveWmsPickSubstitution", () => {
  test("classifies substitution_not_allowed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "substitution_not_allowed: task x is partial (picked=2/short=0) -- a substitution may only be approved before any real progress" } });
    await assert.rejects(
      () =>
        approveWmsPickSubstitution(client, {
          taskId: TASK_ID,
          substituteItemMasterId: OWNER_ID,
          locationId: null,
          lotNumber: null,
          serialNumber: null,
          reason: "supply shortage",
          idempotencyKey: "idem-sub-1",
          expectedVersion: 1,
          actorAuthUserId: SUPERVISOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "substitution_not_allowed",
    );
  });

  test("classifies substitute_item_not_eligible", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "substitute_item_not_eligible: x is not an active item master owned by the task's own account" } });
    await assert.rejects(
      () =>
        approveWmsPickSubstitution(client, {
          taskId: TASK_ID,
          substituteItemMasterId: OWNER_ID,
          locationId: null,
          lotNumber: null,
          serialNumber: null,
          reason: "supply shortage",
          idempotencyKey: "idem-sub-2",
          expectedVersion: 1,
          actorAuthUserId: SUPERVISOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof WmsPickingMutationError && err.code === "substitute_item_not_eligible",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, item_master_id: OWNER_ID, substituted_from_item_master_id: ITEM_ID }], error: null });
    const task = await approveWmsPickSubstitution(client, {
      taskId: TASK_ID,
      substituteItemMasterId: OWNER_ID,
      locationId: null,
      lotNumber: null,
      serialNumber: null,
      reason: "supply shortage",
      idempotencyKey: "idem-sub-3",
      expectedVersion: 1,
      actorAuthUserId: SUPERVISOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(task.itemMasterId, OWNER_ID);
    assert.equal(task.substitutedFromItemMasterId, ITEM_ID);
    assert.equal(calls[0]?.fn, "approve_wms_pick_substitution");
  });
});
