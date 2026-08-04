import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getCustomerInventoryBalance,
  listCustomerInventoryBalances,
  listCustomerLotIdentities,
  listCustomerSerialIdentities,
  getCustomerOutboundOrder,
  listCustomerOutboundOrderLines,
  listCustomerOutboundOrders,
  listCustomerInventoryMovementSummary,
  listCustomerWarehouseEligibility,
  CustomerInventoryAccessQueryError,
  type CustomerInventoryAccessQueryClient,
} from "./customer-inventory-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "823e4567-e89b-12d3-a456-426614174000";
const ORDER_ID = "923e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerInventoryAccessQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerInventoryAccessQueryClient;
  return { client, calls };
}

const BALANCE_ROW = {
  id: BALANCE_ID,
  warehouse_id: WAREHOUSE_ID,
  owner_account_id: OWNER_ID,
  item_master_id: ITEM_ID,
  location_id: LOCATION_ID,
  lot_number: null,
  serial_number: null,
  status: "on_hand",
  on_hand: "10",
  reserved: "0",
  held: "0",
  available: "10",
  record_version: 1,
  updated_at: "2026-08-04T00:00:00.000Z",
};

describe("getCustomerInventoryBalance", () => {
  test("maps the RPC's own single row and passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    const result = await getCustomerInventoryBalance(client, TENANT_ID, ACTOR_ID, BALANCE_ID);
    assert.equal(result.onHand, 10);
    assert.deepEqual(calls[0], {
      fn: "get_customer_inventory_balance",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_balance_id: BALANCE_ID },
    });
  });

  test("propagates the RPC's own record_not_found error message unchanged", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted inventory balance exists for x" } });
    await assert.rejects(() => getCustomerInventoryBalance(client, TENANT_ID, ACTOR_ID, BALANCE_ID), (err: unknown) => {
      assert.ok(err instanceof CustomerInventoryAccessQueryError);
      assert.match(err.message, /^record_not_found/);
      return true;
    });
  });

  test("throws when the RPC returns no row at all", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => getCustomerInventoryBalance(client, TENANT_ID, ACTOR_ID, BALANCE_ID));
  });

  test("on record_not_found, also calls the durable denial-audit RPC with the requested resource id (Prompt 242 §18)", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted inventory balance exists for x" } });
    await assert.rejects(() => getCustomerInventoryBalance(client, TENANT_ID, ACTOR_ID, BALANCE_ID));
    assert.equal(calls.length, 2);
    assert.deepEqual(calls[1], {
      fn: "record_customer_inventory_access_denial",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_resource_type: "inventory_balance", p_resource_id: BALANCE_ID },
    });
  });

  test("does NOT call the denial-audit RPC on a successful read", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    await getCustomerInventoryBalance(client, TENANT_ID, ACTOR_ID, BALANCE_ID);
    assert.equal(calls.length, 1);
  });

  test("a failing denial-audit call never masks the original record_not_found error", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        if (fn === "record_customer_inventory_access_denial") {
          throw new Error("network blip");
        }
        return { data: null, error: { message: "record_not_found: no permitted inventory balance exists for x" } };
      },
    } as unknown as CustomerInventoryAccessQueryClient;
    await assert.rejects(() => getCustomerInventoryBalance(client, TENANT_ID, ACTOR_ID, BALANCE_ID), (err: unknown) => {
      assert.ok(err instanceof CustomerInventoryAccessQueryError);
      assert.match(err.message, /^record_not_found/);
      return true;
    });
    assert.equal(calls.length, 2);
  });
});

describe("listCustomerInventoryBalances", () => {
  test("defaults filters to null and limit to 50, forwards cursor params", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    const result = await listCustomerInventoryBalances(client, TENANT_ID, ACTOR_ID, { cursorUpdatedAt: "2026-08-01T00:00:00.000Z", cursorId: BALANCE_ID });
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_warehouse_id: null,
      p_item_master_id: null,
      p_cursor_updated_at: "2026-08-01T00:00:00.000Z",
      p_cursor_id: BALANCE_ID,
      p_limit: 50,
    });
  });

  test("returns an empty array when the RPC returns null data", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerInventoryBalances(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });
});

describe("listCustomerLotIdentities / listCustomerSerialIdentities", () => {
  test("listCustomerLotIdentities forwards every filter", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerLotIdentities(client, TENANT_ID, ACTOR_ID, { warehouseId: WAREHOUSE_ID, itemMasterId: ITEM_ID, ownerAccountId: OWNER_ID, statusFilter: "held" });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_warehouse_id: WAREHOUSE_ID,
      p_item_master_id: ITEM_ID,
      p_owner_account_id: OWNER_ID,
      p_status_filter: "held",
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 50,
    });
  });

  test("listCustomerSerialIdentities calls the distinct RPC name (not unified with lots)", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerSerialIdentities(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_customer_serial_identities");
  });
});

describe("getCustomerOutboundOrder / listCustomerOutboundOrderLines / listCustomerOutboundOrders", () => {
  const ORDER_ROW = {
    id: ORDER_ID,
    warehouse_id: WAREHOUSE_ID,
    owner_account_id: OWNER_ID,
    outbound_number: "OUT-1",
    source_type: "manual",
    requested_ship_date: null,
    status: "draft",
    cancelled_reason: null,
    record_version: 1,
    created_at: "2026-08-04T00:00:00.000Z",
    updated_at: "2026-08-04T00:00:00.000Z",
  };

  test("getCustomerOutboundOrder maps the row and uses only 3 params (no actor label)", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    const result = await getCustomerOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID);
    assert.equal(result.outboundNumber, "OUT-1");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_outbound_order_id: ORDER_ID });
  });

  test("getCustomerOutboundOrder on record_not_found also calls the durable denial-audit RPC (Prompt 242 §18)", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted outbound order exists for x" } });
    await assert.rejects(() => getCustomerOutboundOrder(client, TENANT_ID, ACTOR_ID, ORDER_ID));
    assert.equal(calls.length, 2);
    assert.deepEqual(calls[1], {
      fn: "record_customer_inventory_access_denial",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_resource_type: "outbound_order", p_resource_id: ORDER_ID },
    });
  });

  test("listCustomerOutboundOrderLines takes no tenantId (derives it server-side)", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerOutboundOrderLines(client, ORDER_ID, ACTOR_ID);
    assert.deepEqual(calls[0]?.args, { p_outbound_order_id: ORDER_ID, p_actor_auth_user_id: ACTOR_ID });
  });

  test("listCustomerOutboundOrders forwards status/warehouse filters and cursor", async () => {
    const { client, calls } = fakeRpcClient({ data: [ORDER_ROW], error: null });
    const result = await listCustomerOutboundOrders(client, TENANT_ID, ACTOR_ID, { warehouseId: WAREHOUSE_ID, statusFilter: "confirmed", limit: 10 });
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_warehouse_id: WAREHOUSE_ID,
      p_status_filter: "confirmed",
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 10,
    });
  });
});

describe("listCustomerInventoryMovementSummary", () => {
  test("uses p_cursor_occurred_at, not p_cursor_updated_at", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerInventoryMovementSummary(client, TENANT_ID, ACTOR_ID, { cursorOccurredAt: "2026-08-01T00:00:00.000Z", cursorId: BALANCE_ID });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_warehouse_id: null,
      p_item_master_id: null,
      p_cursor_occurred_at: "2026-08-01T00:00:00.000Z",
      p_cursor_id: BALANCE_ID,
      p_limit: 50,
    });
  });
});

describe("listCustomerWarehouseEligibility", () => {
  test("takes only tenantId/actorAuthUserId -- no OPS gate, no filters", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "923e4567-e89b-12d3-a456-426614174000",
          warehouse_id: WAREHOUSE_ID,
          customer_account_id: OWNER_ID,
          status: "active",
          granted_at: "2026-08-01T00:00:00.000Z",
          revoked_at: null,
          revoked_reason: null,
          record_version: 1,
        },
      ],
      error: null,
    });
    const result = await listCustomerWarehouseEligibility(client, TENANT_ID, ACTOR_ID);
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
  });
});
