import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getWmsPutawayTask, listWmsPutawayTaskConfirmations, listWmsPutawayTasks, WmsPutawayQueryError, type WmsPutawayQueryClient } from "./wms-putaway.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const TASK_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "b23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsPutawayQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsPutawayQueryClient;
  return { client, calls };
}

const TASK_ROW = {
  id: TASK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: "323e4567-e89b-12d3-a456-426614174000",
  receipt_line_id: "423e4567-e89b-12d3-a456-426614174000",
  source_location_id: "523e4567-e89b-12d3-a456-426614174000",
  item_master_id: "723e4567-e89b-12d3-a456-426614174000",
  owner_account_id: "823e4567-e89b-12d3-a456-426614174000",
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
  suggested_location_id: null,
  suggested_reason: null,
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

describe("getWmsPutawayTask", () => {
  test("maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [TASK_ROW], error: null });
    const task = await getWmsPutawayTask(client, TASK_ID, ACTOR_ID);
    assert.equal(task.status, "unclaimed");
    assert.equal(calls[0]?.fn, "get_wms_putaway_task");
  });

  test("throws when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getWmsPutawayTask(client, TASK_ID, ACTOR_ID), WmsPutawayQueryError);
  });
});

describe("listWmsPutawayTaskConfirmations", () => {
  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listWmsPutawayTaskConfirmations(client, TASK_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listWmsPutawayTasks", () => {
  test("defaults every optional filter to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [TASK_ROW], error: null });
    const rows = await listWmsPutawayTasks(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(calls[0]?.args.p_warehouse_id, null);
    assert.equal(calls[0]?.args.p_receipt_line_id, null);
    assert.equal(calls[0]?.args.p_claimed_by_auth_user_id, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("passes through explicit filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsPutawayTasks(client, TENANT_ID, ACTOR_ID, {
      warehouseId: "323e4567-e89b-12d3-a456-426614174000",
      statusFilter: "claimed",
      claimedByAuthUserId: ACTOR_ID,
      limit: 10,
    });
    assert.equal(calls[0]?.args.p_warehouse_id, "323e4567-e89b-12d3-a456-426614174000");
    assert.equal(calls[0]?.args.p_status_filter, "claimed");
    assert.equal(calls[0]?.args.p_claimed_by_auth_user_id, ACTOR_ID);
    assert.equal(calls[0]?.args.p_limit, 10);
  });
});
