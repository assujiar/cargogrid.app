import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getCycleCountPlan,
  listCycleCountPlans,
  getCycleCountScopeItem,
  listCycleCountScopeItems,
  listCycleCountObservations,
  CycleCountQueryError,
  type CycleCountQueryClient,
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
const OBSERVATION_ID = "b23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CycleCountQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CycleCountQueryClient;
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
  status: "active",
  scope_filter_zone_id: null,
  scope_filter_location_id: null,
  scope_filter_item_master_id: null,
  scope_filter_owner_account_id: null,
  frozen_at: "2026-08-03T00:00:00.000Z",
  closed_at: null,
  idempotency_key: "idem-plan-1",
  record_version: 2,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const SCOPE_ITEM_ROW_VISIBLE = {
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
  status: "pending_review",
  assigned_to_auth_user_id: ACTOR_ID,
  assigned_to_label: "counter",
  assigned_at: "2026-08-03T00:00:00.000Z",
  count_attempt_number: 1,
  last_observed_quantity: "95",
  variance_quantity: "-5",
  variance_pct: "5",
  reviewed_by_auth_user_id: null,
  reviewed_by_label: null,
  reviewed_at: null,
  review_reason: null,
  adjustment_movement_id: null,
  record_version: 2,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const SCOPE_ITEM_ROW_REDACTED = {
  ...SCOPE_ITEM_ROW_VISIBLE,
  snapshot_expected_quantity: null,
  snapshot_record_version: null,
  variance_quantity: null,
  variance_pct: null,
};

describe("getCycleCountPlan", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [PLAN_ROW], error: null });
    const plan = await getCycleCountPlan(client, PLAN_ID, ACTOR_ID);
    assert.equal(plan.status, "active");
    assert.equal(calls[0]?.fn, "get_cycle_count_plan");
    assert.equal(calls[0]?.args.p_plan_id, PLAN_ID);
  });

  test("throws CycleCountQueryError on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "plan_not_found: x" } });
    await assert.rejects(() => getCycleCountPlan(client, PLAN_ID, ACTOR_ID), CycleCountQueryError);
  });

  test("throws CycleCountQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getCycleCountPlan(client, PLAN_ID, ACTOR_ID), CycleCountQueryError);
  });
});

describe("listCycleCountPlans", () => {
  test("defaults p_limit to 50 and forwards optional filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [PLAN_ROW], error: null });
    const plans = await listCycleCountPlans(client, TENANT_ID, ACTOR_ID, { warehouseId: WAREHOUSE_ID, statusFilter: "active" });
    assert.equal(plans.length, 1);
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_status_filter, "active");
  });

  test("passes through a caller-requested limit (server caps at 200)", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCycleCountPlans(client, TENANT_ID, ACTOR_ID, { limit: 500 });
    assert.equal(calls[0]?.args.p_limit, 500);
  });
});

describe("getCycleCountScopeItem", () => {
  test("parses a supervisor (visible) row with expected/variance quantities populated", async () => {
    const { client } = fakeRpcClient({ data: [SCOPE_ITEM_ROW_VISIBLE], error: null });
    const item = await getCycleCountScopeItem(client, SCOPE_ITEM_ID, ACTOR_ID);
    assert.equal(item.snapshotExpectedQuantity, 100);
    assert.equal(item.varianceQuantity, -5);
  });

  test("parses a blind-redacted (plain counter) row with expected/variance quantities null", async () => {
    const { client } = fakeRpcClient({ data: [SCOPE_ITEM_ROW_REDACTED], error: null });
    const item = await getCycleCountScopeItem(client, SCOPE_ITEM_ID, ACTOR_ID);
    assert.equal(item.snapshotExpectedQuantity, null);
    assert.equal(item.varianceQuantity, null);
    assert.equal(item.variancePct, null);
    assert.equal(item.snapshotRecordVersion, null);
  });
});

describe("listCycleCountScopeItems", () => {
  test("bounded read forwarding optional filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [SCOPE_ITEM_ROW_VISIBLE], error: null });
    const items = await listCycleCountScopeItems(client, TENANT_ID, ACTOR_ID, { planId: PLAN_ID, statusFilter: "pending_review", assignedToAuthUserId: ACTOR_ID });
    assert.equal(items.length, 1);
    assert.equal(calls[0]?.fn, "list_cycle_count_scope_items");
    assert.equal(calls[0]?.args.p_limit, 50);
  });
});

describe("listCycleCountObservations", () => {
  test("sends the mapped RPC args and parses the returned observations", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: OBSERVATION_ID,
          tenant_id: TENANT_ID,
          scope_item_id: SCOPE_ITEM_ID,
          attempt_number: 1,
          observed_quantity: "95",
          observed_uom_code: "PCS",
          scanned_location_id: LOCATION_ID,
          scanned_item_master_id: ITEM_ID,
          scanned_lot_number: null,
          scanned_serial_number: null,
          idempotency_key: "idem-obs-1",
          counted_by_auth_user_id: ACTOR_ID,
          counted_by_label: "counter",
          counted_at: "2026-08-03T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const observations = await listCycleCountObservations(client, SCOPE_ITEM_ID, ACTOR_ID);
    assert.equal(observations.length, 1);
    assert.equal(observations[0]?.observedQuantity, 95);
    assert.equal(calls[0]?.fn, "list_cycle_count_observations");
  });
});
