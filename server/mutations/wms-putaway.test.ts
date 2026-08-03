import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  generateWmsPutawayTask,
  claimWmsPutawayTask,
  confirmWmsPutawayTask,
  markWmsPutawayTaskException,
  reassignWmsPutawayTask,
  cancelWmsPutawayTask,
  WmsPutawayMutationError,
  type WmsPutawayMutationRpcClient,
} from "./wms-putaway.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const RECEIPT_LINE_ID = "423e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const TASK_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const SUPERVISOR_ID = "a23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsPutawayMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsPutawayMutationRpcClient;
  return { client, calls };
}

const TASK_ROW = {
  id: TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  receipt_line_id: RECEIPT_LINE_ID,
  source_location_id: LOCATION_ID,
  item_master_id: ITEM_ID,
  owner_account_id: OWNER_ID,
  uom_code: "PCS",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  lot_number: null,
  serial_number: null,
  expiry_date: null,
  task_quantity: "50",
  confirmed_quantity: "0",
  remaining_quantity: "50",
  suggested_location_id: LOCATION_ID,
  suggested_reason: "auto_suggested_first_eligible_capacity_headroom",
  actual_location_id: null,
  status: "unclaimed",
  claimed_by_auth_user_id: null,
  claimed_by_label: null,
  claimed_at: null,
  exception_reason: null,
  idempotency_key: "idem-task-1",
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("generateWmsPutawayTask", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TASK_ROW], error: null });
    const task = await generateWmsPutawayTask(client, {
      receiptLineId: RECEIPT_LINE_ID,
      quantity: 50,
      suggestedLocationId: null,
      idempotencyKey: "idem-task-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(task.receiptLineId, RECEIPT_LINE_ID);
    assert.equal(calls[0]?.fn, "generate_wms_putaway_task");
    assert.equal(calls[0]?.args.p_suggested_location_id, null);
  });

  test("classifies insufficient_remaining_quantity", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_remaining_quantity: 10 of 50 accepted units remain un-put-away for receipt line x, requested 20" } });
    await assert.rejects(
      () =>
        generateWmsPutawayTask(client, {
          receiptLineId: RECEIPT_LINE_ID,
          quantity: 20,
          suggestedLocationId: null,
          idempotencyKey: "idem-task-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "insufficient_remaining_quantity",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        generateWmsPutawayTask(client, {
          receiptLineId: RECEIPT_LINE_ID,
          quantity: 20,
          suggestedLocationId: null,
          idempotencyKey: "idem-task-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "mutation_failed",
    );
  });
});

describe("claimWmsPutawayTask", () => {
  test("classifies task_already_claimed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "task_already_claimed: task x is claimed (claimed_by=other-picker) -- only an unclaimed task may be claimed" } });
    await assert.rejects(
      () => claimWmsPutawayTask(client, { taskId: TASK_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "picker" }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "task_already_claimed",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "claimed", claimed_by_auth_user_id: ACTOR_ID, claimed_by_label: "picker", claimed_at: "2026-08-03T00:00:00.000Z" }], error: null });
    const task = await claimWmsPutawayTask(client, { taskId: TASK_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "picker" });
    assert.equal(task.status, "claimed");
    assert.equal(calls[0]?.fn, "claim_wms_putaway_task");
  });
});

describe("confirmWmsPutawayTask", () => {
  test("classifies not_task_claimant", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "not_task_claimant: identity x is not the assigned claimant of task y" } });
    await assert.rejects(
      () =>
        confirmWmsPutawayTask(client, {
          taskId: TASK_ID,
          quantity: 50,
          actualLocationId: LOCATION_ID,
          lotNumber: null,
          serialNumber: null,
          idempotencyKey: "idem-confirm-1",
          expectedVersion: 2,
          actorAuthUserId: SUPERVISOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "not_task_claimant",
    );
  });

  test("classifies destination_full", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "destination_full: destination x has 45 of 50 capacity occupied -- 20 more would exceed it" } });
    await assert.rejects(
      () =>
        confirmWmsPutawayTask(client, {
          taskId: TASK_ID,
          quantity: 20,
          actualLocationId: LOCATION_ID,
          lotNumber: null,
          serialNumber: null,
          idempotencyKey: "idem-confirm-2",
          expectedVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "picker",
        }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "destination_full",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "confirmed", confirmed_quantity: "50", remaining_quantity: "0", actual_location_id: LOCATION_ID }], error: null });
    const task = await confirmWmsPutawayTask(client, {
      taskId: TASK_ID,
      quantity: 50,
      actualLocationId: LOCATION_ID,
      lotNumber: null,
      serialNumber: null,
      idempotencyKey: "idem-confirm-3",
      expectedVersion: 2,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "picker",
    });
    assert.equal(task.status, "confirmed");
    assert.equal(calls[0]?.fn, "confirm_wms_putaway_task");
    assert.equal(calls[0]?.args.p_quantity, 50);
  });
});

describe("markWmsPutawayTaskException", () => {
  test("classifies invalid_transition", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_transition: task x is unclaimed -- only a claimed or partially-confirmed task may be marked exception" } });
    await assert.rejects(
      () => markWmsPutawayTaskException(client, { taskId: TASK_ID, reason: "bin blocked by pallet", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "picker" }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "invalid_transition",
    );
  });
});

describe("reassignWmsPutawayTask", () => {
  test("sends a null newClaimantAuthUserId through unchanged (release path)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "unclaimed" }], error: null });
    const task = await reassignWmsPutawayTask(client, {
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
        reassignWmsPutawayTask(client, {
          taskId: TASK_ID,
          newClaimantAuthUserId: null,
          newClaimantLabel: null,
          reason: "attempted reassign",
          expectedVersion: 2,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "picker",
        }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "insufficient_authority",
    );
  });
});

describe("cancelWmsPutawayTask", () => {
  test("classifies has_confirmed_quantity", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "has_confirmed_quantity: task x has already confirmed 10 unit(s) -- a task with real posted movements may never be cancelled, only completed or reassigned" } });
    await assert.rejects(
      () => cancelWmsPutawayTask(client, { taskId: TASK_ID, reason: "duplicate task", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof WmsPutawayMutationError && err.code === "has_confirmed_quantity",
    );
  });

  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...TASK_ROW, status: "cancelled" }], error: null });
    const task = await cancelWmsPutawayTask(client, { taskId: TASK_ID, reason: "duplicate task", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(task.status, "cancelled");
    assert.equal(calls[0]?.fn, "cancel_wms_putaway_task");
  });
});
