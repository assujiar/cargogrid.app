import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getWmsPickTask,
  listWmsPickTaskConfirmations,
  listWmsPickTaskShorts,
  listWmsPickSubstitutionApprovals,
  listWmsPickTasks,
  listWmsPickWaves,
  WmsPickingQueryError,
  type WmsPickingQueryClient,
} from "./wms-picking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const TASK_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsPickingQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsPickingQueryClient;
  return { client, calls };
}

const TASK_ROW = {
  id: TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  outbound_order_id: "423e4567-e89b-12d3-a456-426614174000",
  outbound_order_line_id: "523e4567-e89b-12d3-a456-426614174000",
  wave_id: null,
  owner_account_id: "823e4567-e89b-12d3-a456-426614174000",
  item_master_id: "723e4567-e89b-12d3-a456-426614174000",
  uom_code: "PCS",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  source_location_id: "a23e4567-e89b-12d3-a456-426614174000",
  lot_number: null,
  serial_number: null,
  expiry_date: null,
  reservation_id: "b23e4567-e89b-12d3-a456-426614174000",
  task_quantity: "50",
  picked_quantity: "0",
  short_quantity: "0",
  remaining_quantity: "50",
  suggested_destination_location_id: null,
  suggested_destination_reason: null,
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

describe("getWmsPickTask", () => {
  test("maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TASK_ROW], error: null });
    const task = await getWmsPickTask(client, TASK_ID, ACTOR_ID);
    assert.equal(task.status, "unclaimed");
    assert.equal(calls[0]?.fn, "get_wms_pick_task");
  });

  test("throws when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getWmsPickTask(client, TASK_ID, ACTOR_ID), WmsPickingQueryError);
  });

  test("propagates an rpc error as WmsPickingQueryError", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x is not owner-scoped to view pick task y" } });
    await assert.rejects(() => getWmsPickTask(client, TASK_ID, ACTOR_ID), WmsPickingQueryError);
  });
});

describe("listWmsPickTaskConfirmations", () => {
  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listWmsPickTaskConfirmations(client, TASK_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listWmsPickTaskShorts", () => {
  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listWmsPickTaskShorts(client, TASK_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listWmsPickSubstitutionApprovals", () => {
  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listWmsPickSubstitutionApprovals(client, TASK_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listWmsPickTasks", () => {
  test("defaults every optional filter to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [TASK_ROW], error: null });
    const rows = await listWmsPickTasks(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(calls[0]?.args.p_warehouse_id, null);
    assert.equal(calls[0]?.args.p_outbound_order_id, null);
    assert.equal(calls[0]?.args.p_wave_id, null);
    assert.equal(calls[0]?.args.p_owner_account_id, null);
    assert.equal(calls[0]?.args.p_claimed_by_auth_user_id, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("passes through explicit filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsPickTasks(client, TENANT_ID, ACTOR_ID, {
      warehouseId: WAREHOUSE_ID,
      statusFilter: "claimed",
      claimedByAuthUserId: ACTOR_ID,
      limit: 10,
    });
    assert.equal(calls[0]?.args.p_warehouse_id, WAREHOUSE_ID);
    assert.equal(calls[0]?.args.p_status_filter, "claimed");
    assert.equal(calls[0]?.args.p_claimed_by_auth_user_id, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 10);
  });
});

describe("listWmsPickWaves", () => {
  test("defaults limit to 50 and warehouse filter to null", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsPickWaves(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.args.p_warehouse_id, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });
});
