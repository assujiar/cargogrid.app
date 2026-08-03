import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getWmsReceiptSession, listWmsReceiptLines, listWmsReceiptSessions, WmsReceivingQueryError, type WmsReceivingQueryClient } from "./wms-receiving.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SESSION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "b23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsReceivingQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsReceivingQueryClient;
  return { client, calls };
}

const SESSION_ROW = {
  id: SESSION_ID,
  tenant_id: TENANT_ID,
  warehouse_id: "323e4567-e89b-12d3-a456-426614174000",
  inbound_order_id: "423e4567-e89b-12d3-a456-426614174000",
  receiving_location_id: "523e4567-e89b-12d3-a456-426614174000",
  idempotency_key: "idem-1",
  status: "in_progress",
  cancelled_reason: null,
  started_by: "rep",
  started_at: "2026-08-03T00:00:00.000Z",
  completed_at: null,
  record_version: 1,
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("getWmsReceiptSession", () => {
  test("maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [SESSION_ROW], error: null });
    const session = await getWmsReceiptSession(client, SESSION_ID, ACTOR_ID);
    assert.equal(session.status, "in_progress");
    assert.equal(calls[0]?.fn, "get_wms_receipt_session");
  });

  test("throws when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getWmsReceiptSession(client, SESSION_ID, ACTOR_ID), WmsReceivingQueryError);
  });
});

describe("listWmsReceiptLines", () => {
  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const lines = await listWmsReceiptLines(client, SESSION_ID, ACTOR_ID);
    assert.deepEqual(lines, []);
  });
});

describe("listWmsReceiptSessions", () => {
  test("defaults every optional filter to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [SESSION_ROW], error: null });
    const rows = await listWmsReceiptSessions(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(calls[0]?.args.p_warehouse_id, null);
    assert.equal(calls[0]?.args.p_inbound_order_id, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("passes through explicit filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsReceiptSessions(client, TENANT_ID, ACTOR_ID, { warehouseId: "323e4567-e89b-12d3-a456-426614174000", statusFilter: "completed", limit: 10 });
    assert.equal(calls[0]?.args.p_warehouse_id, "323e4567-e89b-12d3-a456-426614174000");
    assert.equal(calls[0]?.args.p_status_filter, "completed");
    assert.equal(calls[0]?.args.p_limit, 10);
  });
});
