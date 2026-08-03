import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getItemMaster,
  resolveItemMasterByCode,
  listItemMasters,
  validateUomCode,
  convertUomQuantity,
  ItemUomMasterQueryError,
  type ItemUomMasterQueryClient,
} from "./item-uom-master.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ItemUomMasterQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ItemUomMasterQueryClient;
  return { client, calls };
}

const ITEM_ROW = {
  id: ITEM_ID,
  tenant_id: TENANT_ID,
  owner_account_id: ACCOUNT_ID,
  code: "SKU-100",
  name: "Test Widget",
  description: null,
  base_uom_code: "PCS",
  lot_controlled: false,
  serial_controlled: false,
  expiry_controlled: false,
  status: "active",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

describe("getItemMaster", () => {
  test("maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const item = await getItemMaster(client, ITEM_ID, ACTOR_ID);
    assert.equal(item.code, "SKU-100");
    assert.equal(calls[0]?.fn, "get_item_master");
  });

  test("throws ItemUomMasterQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getItemMaster(client, ITEM_ID, ACTOR_ID), ItemUomMasterQueryError);
  });

  test("throws on an RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "item_master_not_found: nope" } });
    await assert.rejects(() => getItemMaster(client, ITEM_ID, ACTOR_ID), ItemUomMasterQueryError);
  });
});

describe("resolveItemMasterByCode", () => {
  test("passes tenant/owner/code through and maps the result", async () => {
    const { client, calls } = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const item = await resolveItemMasterByCode(client, TENANT_ID, ACCOUNT_ID, "SKU-100", ACTOR_ID);
    assert.equal(item.id, ITEM_ID);
    assert.equal(calls[0]?.args.p_code, "SKU-100");
    assert.equal(calls[0]?.args.p_owner_account_id, ACCOUNT_ID);
  });
});

describe("listItemMasters", () => {
  test("defaults every optional filter to null and limit to 50", async () => {
    const { client, calls } = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const rows = await listItemMasters(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(calls[0]?.args.p_owner_account_id, null);
    assert.equal(calls[0]?.args.p_status_filter, null);
    assert.equal(calls[0]?.args.p_search, null);
    assert.equal(calls[0]?.args.p_limit, 50);
  });

  test("passes through explicit owner/status/search/limit options", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listItemMasters(client, TENANT_ID, ACTOR_ID, { ownerAccountId: ACCOUNT_ID, statusFilter: "inactive", search: "widget", limit: 10 });
    assert.equal(calls[0]?.args.p_owner_account_id, ACCOUNT_ID);
    assert.equal(calls[0]?.args.p_status_filter, "inactive");
    assert.equal(calls[0]?.args.p_search, "widget");
    assert.equal(calls[0]?.args.p_limit, 10);
  });

  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listItemMasters(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("validateUomCode", () => {
  test("returns true/false from the raw RPC boolean", async () => {
    const { client: trueClient } = fakeRpcClient({ data: true, error: null });
    assert.equal(await validateUomCode(trueClient, "KG"), true);
    const { client: falseClient } = fakeRpcClient({ data: false, error: null });
    assert.equal(await validateUomCode(falseClient, "NOPE"), false);
  });
});

describe("convertUomQuantity", () => {
  test("returns the numeric conversion result", async () => {
    const { client, calls } = fakeRpcClient({ data: 2000, error: null });
    const result = await convertUomQuantity(client, 2, "KG", "G");
    assert.equal(result, 2000);
    assert.equal(calls[0]?.args.p_from_uom_code, "KG");
    assert.equal(calls[0]?.args.p_to_uom_code, "G");
  });

  test("throws on an unregistered conversion path", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "uom_conversion_not_registered: no conversion path from KG to L" } });
    await assert.rejects(() => convertUomQuantity(client, 1, "KG", "L"), ItemUomMasterQueryError);
  });
});
