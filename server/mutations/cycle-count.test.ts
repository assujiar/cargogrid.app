import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createCycleCountPlan,
  freezeCycleCountScope,
  cancelCycleCountPlan,
  closeCycleCountPlan,
  assignCycleCountScopeItem,
  recordCycleCountObservation,
  approveCycleCountVariance,
  rejectCycleCountVariance,
  cancelCycleCountScopeItem,
  CycleCountMutationError,
  type CycleCountMutationRpcClient,
} from "./cycle-count.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const PLAN_ID = "423e4567-e89b-12d3-a456-426614174000";
const SCOPE_ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "923e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "a23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CycleCountMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CycleCountMutationRpcClient;
  return { client, calls };
}

const PLAN_ROW = {
  id: PLAN_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  plan_number: "CC-2026-000001",
  method: "full",
  variance_threshold_pct: "0",
  recount_threshold_pct: "5",
  requires_separate_approver: true,
  status: "draft",
  scope_filter_zone_id: null,
  scope_filter_location_id: null,
  scope_filter_item_master_id: null,
  scope_filter_owner_account_id: null,
  frozen_at: null,
  closed_at: null,
  idempotency_key: "idem-plan-1",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const SCOPE_ITEM_ROW = {
  id: SCOPE_ITEM_ID,
  tenant_id: TENANT_ID,
  plan_id: PLAN_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  location_id: LOCATION_ID,
  lot_number: null,
  serial_number: null,
  uom_code: "PCS",
  snapshot_balance_id: BALANCE_ID,
  snapshot_expected_quantity: "100",
  snapshot_record_version: 1,
  snapshot_taken_at: "2026-08-03T00:00:00.000Z",
  status: "pending",
  assigned_to_auth_user_id: null,
  assigned_to_label: null,
  assigned_at: null,
  count_attempt_number: 0,
  last_observed_quantity: null,
  variance_quantity: null,
  variance_pct: null,
  reviewed_by_auth_user_id: null,
  reviewed_by_label: null,
  reviewed_at: null,
  review_reason: null,
  adjustment_movement_id: null,
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("createCycleCountPlan", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [PLAN_ROW], error: null });
    const plan = await createCycleCountPlan(client, {
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      varianceThresholdPct: 0,
      recountThresholdPct: 5,
      idempotencyKey: "idem-plan-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(plan.planNumber, "CC-2026-000001");
    assert.equal(calls[0]?.fn, "create_cycle_count_plan");
    assert.equal(calls[0]?.args.p_method, null);
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:Create (no_matching_role) for tenant y" } });
    await assert.rejects(
      () =>
        createCycleCountPlan(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          varianceThresholdPct: 0,
          recountThresholdPct: 5,
          idempotencyKey: "idem-plan-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "insufficient_authority",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        createCycleCountPlan(client, {
          tenantId: TENANT_ID,
          warehouseId: WAREHOUSE_ID,
          varianceThresholdPct: 0,
          recountThresholdPct: 5,
          idempotencyKey: "idem-plan-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "mutation_failed",
    );
  });
});

describe("freezeCycleCountScope", () => {
  test("sends the mapped RPC args and parses the returned scope items", async () => {
    const { client, calls } = fakeRpcClient({ data: [SCOPE_ITEM_ROW], error: null });
    const items = await freezeCycleCountScope(client, { planId: PLAN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(items.length, 1);
    assert.equal(items[0]?.snapshotBalanceId, BALANCE_ID);
    assert.equal(calls[0]?.fn, "freeze_cycle_count_scope");
  });

  test("an empty match returns an empty array, not an error", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const items = await freezeCycleCountScope(client, { planId: PLAN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.deepEqual(items, []);
  });

  test("classifies freeze_already_done", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "freeze_already_done: plan x is active -- only a draft plan may be frozen" } });
    await assert.rejects(
      () => freezeCycleCountScope(client, { planId: PLAN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "freeze_already_done",
    );
  });
});

describe("assignCycleCountScopeItem", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SCOPE_ITEM_ROW, status: "assigned", assigned_to_auth_user_id: ACTOR_ID }], error: null });
    const item = await assignCycleCountScopeItem(client, {
      scopeItemId: SCOPE_ITEM_ID,
      assigneeAuthUserId: ACTOR_ID,
      assigneeLabel: "counter",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(item.status, "assigned");
    assert.equal(calls[0]?.fn, "assign_cycle_count_scope_item");
  });

  test("classifies task_not_assignable", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "task_not_assignable: scope item x is assigned -- only a pending or recount_required item may be assigned" } });
    await assert.rejects(
      () =>
        assignCycleCountScopeItem(client, {
          scopeItemId: SCOPE_ITEM_ID,
          assigneeAuthUserId: ACTOR_ID,
          assigneeLabel: "counter",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "task_not_assignable",
    );
  });
});

describe("recordCycleCountObservation", () => {
  test("accepts and sends an explicit zero observed quantity", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SCOPE_ITEM_ROW, status: "no_variance_closed", last_observed_quantity: "0", variance_quantity: "0", variance_pct: "0" }], error: null });
    const item = await recordCycleCountObservation(client, {
      scopeItemId: SCOPE_ITEM_ID,
      observedQuantity: 0,
      observedUomCode: "PCS",
      scannedLocationId: LOCATION_ID,
      scannedItemMasterId: ITEM_ID,
      idempotencyKey: "idem-obs-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "counter",
    });
    assert.equal(item.status, "no_variance_closed");
    assert.equal(calls[0]?.args.p_observed_quantity, 0);
  });

  test("classifies location_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "location_mismatch: scanned location x does not match scope item y's own location z" } });
    await assert.rejects(
      () =>
        recordCycleCountObservation(client, {
          scopeItemId: SCOPE_ITEM_ID,
          observedQuantity: 5,
          observedUomCode: "PCS",
          scannedLocationId: LOCATION_ID,
          scannedItemMasterId: ITEM_ID,
          idempotencyKey: "idem-obs-2",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "counter",
        }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "location_mismatch",
    );
  });

  test("classifies not_scope_item_claimant", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "not_scope_item_claimant: identity x is not the assigned counter of scope item y" } });
    await assert.rejects(
      () =>
        recordCycleCountObservation(client, {
          scopeItemId: SCOPE_ITEM_ID,
          observedQuantity: 5,
          observedUomCode: "PCS",
          scannedLocationId: LOCATION_ID,
          scannedItemMasterId: ITEM_ID,
          idempotencyKey: "idem-obs-3",
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "counter",
        }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "not_scope_item_claimant",
    );
  });
});

describe("approveCycleCountVariance", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SCOPE_ITEM_ROW, status: "adjusted" }], error: null });
    const item = await approveCycleCountVariance(client, {
      scopeItemId: SCOPE_ITEM_ID,
      expectedVersion: 1,
      reason: "confirmed variance",
      idempotencyKey: "idem-approve-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(item.status, "adjusted");
    assert.equal(calls[0]?.fn, "approve_cycle_count_variance");
  });

  test("classifies self_approval_not_allowed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "self_approval_not_allowed: identity x submitted the most recent count for scope item y and may not also approve its own variance" } });
    await assert.rejects(
      () =>
        approveCycleCountVariance(client, {
          scopeItemId: SCOPE_ITEM_ID,
          expectedVersion: 1,
          reason: "confirmed variance",
          idempotencyKey: "idem-approve-2",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "self_approval_not_allowed",
    );
  });

  test("classifies balance_changed_since_snapshot", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "balance_changed_since_snapshot: balance x has changed since scope item y's own snapshot was taken (expected version 1, found 2)" } });
    await assert.rejects(
      () =>
        approveCycleCountVariance(client, {
          scopeItemId: SCOPE_ITEM_ID,
          expectedVersion: 1,
          reason: "confirmed variance",
          idempotencyKey: "idem-approve-3",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "supervisor",
        }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "balance_changed_since_snapshot",
    );
  });
});

describe("rejectCycleCountVariance", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SCOPE_ITEM_ROW, status: "recount_required" }], error: null });
    const item = await rejectCycleCountVariance(client, {
      scopeItemId: SCOPE_ITEM_ID,
      expectedVersion: 1,
      reason: "needs a recount",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "supervisor",
    });
    assert.equal(item.status, "recount_required");
    assert.equal(calls[0]?.fn, "reject_cycle_count_variance");
  });
});

describe("cancelCycleCountPlan", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PLAN_ROW, status: "cancelled" }], error: null });
    const plan = await cancelCycleCountPlan(client, { planId: PLAN_ID, reason: "abandoned", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(plan.status, "cancelled");
    assert.equal(calls[0]?.fn, "cancel_cycle_count_plan");
  });
});

describe("closeCycleCountPlan", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...PLAN_ROW, status: "closed" }], error: null });
    const plan = await closeCycleCountPlan(client, { planId: PLAN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(plan.status, "closed");
    assert.equal(calls[0]?.fn, "close_cycle_count_plan");
  });

  test("classifies plan_has_unresolved_scope_items", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "plan_has_unresolved_scope_items: plan x has 2 unresolved scope item(s)" } });
    await assert.rejects(
      () => closeCycleCountPlan(client, { planId: PLAN_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "plan_has_unresolved_scope_items",
    );
  });
});

describe("cancelCycleCountScopeItem", () => {
  test("sends the mapped RPC args", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...SCOPE_ITEM_ROW, status: "cancelled" }], error: null });
    const item = await cancelCycleCountScopeItem(client, { scopeItemId: SCOPE_ITEM_ID, reason: "location no longer relevant", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" });
    assert.equal(item.status, "cancelled");
    assert.equal(calls[0]?.fn, "cancel_cycle_count_scope_item");
  });

  test("classifies scope_item_already_resolved", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "scope_item_already_resolved: scope item x is adjusted -- a resolved item may never be cancelled" } });
    await assert.rejects(
      () => cancelCycleCountScopeItem(client, { scopeItemId: SCOPE_ITEM_ID, reason: "oops", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "supervisor" }),
      (err: unknown) => err instanceof CycleCountMutationError && err.code === "scope_item_already_resolved",
    );
  });
});
