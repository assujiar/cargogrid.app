import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getWmsOutboundOrder,
  listWmsOutboundOrderLines,
  listWmsOutboundOrders,
  getWmsOutboundReadiness,
  WmsOutboundOrderQueryError,
  type WmsOutboundOrderQueryClient,
} from "./wms-outbound-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ORDER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WmsOutboundOrderQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WmsOutboundOrderQueryClient;
  return { client, calls };
}

const ORDER_ROW = {
  id: ORDER_ID,
  tenant_id: TENANT_ID,
  warehouse_id: "323e4567-e89b-12d3-a456-426614174000",
  owner_account_id: "523e4567-e89b-12d3-a456-426614174000",
  outbound_number: "WMSOUT-2026-000001",
  source_type: "manual",
  source_shipment_order_id: null,
  source_reason: "no order yet",
  idempotency_key: "idem-1",
  requested_ship_date: null,
  status: "draft",
  cancelled_reason: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("getWmsOutboundOrder", () => {
  test("maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    const order = await getWmsOutboundOrder(client, ORDER_ID, ACTOR_ID);
    assert.equal(order.outboundNumber, "WMSOUT-2026-000001");
    assert.equal(calls[0]?.fn, "get_wms_outbound_order");
  });

  test("throws when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getWmsOutboundOrder(client, ORDER_ID, ACTOR_ID), WmsOutboundOrderQueryError);
  });
});

describe("listWmsOutboundOrderLines", () => {
  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const lines = await listWmsOutboundOrderLines(client, ORDER_ID, ACTOR_ID);
    assert.deepEqual(lines, []);
  });
});

describe("listWmsOutboundOrders", () => {
  test("defaults every optional filter to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    const rows = await listWmsOutboundOrders(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(calls[0]?.args.p_warehouse_id, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("passes through explicit filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWmsOutboundOrders(client, TENANT_ID, ACTOR_ID, { warehouseId: "323e4567-e89b-12d3-a456-426614174000", statusFilter: "confirmed", limit: 10 });
    assert.equal(calls[0]?.args.p_warehouse_id, "323e4567-e89b-12d3-a456-426614174000");
    assert.equal(calls[0]?.args.p_status_filter, "confirmed");
    assert.equal(calls[0]?.args.p_limit, 10);
  });
});

describe("getWmsOutboundReadiness", () => {
  test("maps a not-ready readiness row", async () => {
    const { client } = fakeRpcClient({
      data: [{ has_lines: true, warehouse_active: true, owner_active: true, source_shipment_valid: true, invalid_line_count: 1, ready: false }],
      error: null,
    });
    const readiness = await getWmsOutboundReadiness(client, ORDER_ID, ACTOR_ID);
    assert.equal(readiness.ready, false);
    assert.equal(readiness.invalidLineCount, 1);
  });

  test("throws when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getWmsOutboundReadiness(client, ORDER_ID, ACTOR_ID), WmsOutboundOrderQueryError);
  });
});
