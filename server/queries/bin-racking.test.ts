import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listWarehouseLocations, getWarehouseLocationDeactivationImpact, resolveWarehouseLocationByBarcode, BinRackingQueryError, type BinRackingQueryClient } from "./bin-racking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const RACK_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: BinRackingQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as BinRackingQueryClient;
  return { client, calls };
}

const RACK_ROW = {
  id: RACK_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  zone_id: null,
  parent_id: null,
  code: "RACK-A",
  name: "Rack A",
  location_type: "rack",
  path: [],
  depth: 0,
  sequence: 1,
  capacity_value: null,
  capacity_uom: null,
  environment: {},
  restrictions: {},
  barcode: "BC-RACK-A",
  pick_enabled: false,
  putaway_enabled: false,
  status: "draft",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("listWarehouseLocations", () => {
  test("maps root nodes and passes null parent/status filters by default", async () => {
    const { client, calls } = fakeRpcClient({ data: [RACK_ROW], error: null });
    const rows = await listWarehouseLocations(client, WAREHOUSE_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.code, "RACK-A");
    assert.equal(calls[0]?.fn, "list_warehouse_locations");
    assert.equal(calls[0]?.args.p_parent_id, null);
    assert.equal(calls[0]?.args.p_status_filter, null);
  });

  test("passes an explicit parent id and status filter", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listWarehouseLocations(client, WAREHOUSE_ID, ACTOR_ID, RACK_ID, "active");
    assert.equal(calls[0]?.args.p_parent_id, RACK_ID);
    assert.equal(calls[0]?.args.p_status_filter, "active");
  });

  test("throws BinRackingQueryError on an rpc error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
    await assert.rejects(() => listWarehouseLocations(client, WAREHOUSE_ID, ACTOR_ID), BinRackingQueryError);
  });
});

describe("getWarehouseLocationDeactivationImpact", () => {
  test("maps the impact preview", async () => {
    const { client } = fakeRpcClient({ data: { active_child_count: 0, draft_child_count: 1 }, error: null });
    const impact = await getWarehouseLocationDeactivationImpact(client, RACK_ID, ACTOR_ID);
    assert.equal(impact.draftChildCount, 1);
  });
});

describe("resolveWarehouseLocationByBarcode", () => {
  test("resolves a barcode to its location", async () => {
    const { client, calls } = fakeRpcClient({ data: RACK_ROW, error: null });
    const location = await resolveWarehouseLocationByBarcode(client, TENANT_ID, "BC-RACK-A", ACTOR_ID);
    assert.equal(location.code, "RACK-A");
    assert.equal(calls[0]?.args.p_barcode, "BC-RACK-A");
  });

  test("throws BinRackingQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => resolveWarehouseLocationByBarcode(client, TENANT_ID, "BC-UNKNOWN", ACTOR_ID), BinRackingQueryError);
  });
});
