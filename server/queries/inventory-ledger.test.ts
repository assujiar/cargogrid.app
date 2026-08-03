import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getInventoryBalance, listInventoryBalances, listInventoryMovements, listInventoryMovementLines, InventoryLedgerQueryError, type InventoryLedgerQueryClient } from "./inventory-ledger.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const MOVEMENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: InventoryLedgerQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as InventoryLedgerQueryClient;
  return { client, calls };
}

const BALANCE_ROW = {
  id: "a23e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: ACCOUNT_ID,
  item_master_id: ITEM_ID,
  location_id: LOCATION_ID,
  lot_number: null,
  serial_number: null,
  status: "on_hand",
  on_hand: "100",
  reserved: "0",
  held: "0",
  available: "100",
  record_version: 1,
  updated_at: "2026-08-03T00:00:00.000Z",
};

const MOVEMENT_ROW = {
  id: MOVEMENT_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  movement_type: "opening_balance",
  source_type: "opening_balance",
  source_id: null,
  idempotency_key: "idem-open-1",
  corrects_movement_id: null,
  reason: null,
  occurred_at: "2026-08-03T00:00:00.000Z",
  posted_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
};

const LINE_ROW = {
  id: "923e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  movement_id: MOVEMENT_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: ACCOUNT_ID,
  item_master_id: ITEM_ID,
  location_id: LOCATION_ID,
  uom_code: "PCS",
  signed_quantity: "100",
  lot_number: null,
  serial_number: null,
  expiry_date: null,
  status: "on_hand",
  created_at: "2026-08-03T00:00:00.000Z",
};

describe("getInventoryBalance", () => {
  test("maps the single returned row", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    const balance = await getInventoryBalance(
      client,
      { tenantId: TENANT_ID, warehouseId: WAREHOUSE_ID, ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, status: "on_hand" },
      ACTOR_ID,
    );
    assert.equal(balance.onHand, 100);
    assert.equal(calls[0]?.fn, "get_inventory_balance");
  });

  test("throws when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () => getInventoryBalance(client, { tenantId: TENANT_ID, warehouseId: WAREHOUSE_ID, ownerAccountId: ACCOUNT_ID, itemMasterId: ITEM_ID, locationId: LOCATION_ID, status: "on_hand" }, ACTOR_ID),
      InventoryLedgerQueryError,
    );
  });
});

describe("listInventoryBalances", () => {
  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const balances = await listInventoryBalances(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(balances, []);
  });

  test("passes bounded default limit and filters through", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    await listInventoryBalances(client, TENANT_ID, ACTOR_ID, { warehouseId: WAREHOUSE_ID, itemMasterId: ITEM_ID });
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_warehouse_id, WAREHOUSE_ID);
    assert.equal(calls[0]?.args.p_item_master_id, ITEM_ID);
  });
});

describe("listInventoryMovements", () => {
  test("maps returned rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [MOVEMENT_ROW], error: null });
    const movements = await listInventoryMovements(client, TENANT_ID, ACTOR_ID, { movementType: "opening_balance" });
    assert.equal(movements[0]?.movementType, "opening_balance");
    assert.equal(calls[0]?.fn, "list_inventory_movements");
  });

  test("throws InventoryLedgerQueryError on RPC error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks OPS:View" } });
    await assert.rejects(() => listInventoryMovements(client, TENANT_ID, ACTOR_ID), InventoryLedgerQueryError);
  });
});

describe("listInventoryMovementLines", () => {
  test("maps returned rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [LINE_ROW], error: null });
    const lines = await listInventoryMovementLines(client, MOVEMENT_ID, ACTOR_ID);
    assert.equal(lines[0]?.signedQuantity, 100);
    assert.equal(calls[0]?.fn, "list_inventory_movement_lines");
  });
});
