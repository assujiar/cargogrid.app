import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { exportCustomerInventorySnapshot, CustomerInventoryAccessMutationError, type CustomerInventoryAccessMutationRpcClient } from "./customer-inventory-access.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "423e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerInventoryAccessMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerInventoryAccessMutationRpcClient;
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

describe("exportCustomerInventorySnapshot", () => {
  test("defaults limit to 500 and actorLabel to null, forwards warehouse/item filters", async () => {
    const { client, calls } = fakeRpcClient({ data: [BALANCE_ROW], error: null });
    const result = await exportCustomerInventorySnapshot(client, {
      tenantId: TENANT_ID,
      actorAuthUserId: ACTOR_ID,
      warehouseId: WAREHOUSE_ID,
      itemMasterId: ITEM_ID,
    });
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0], {
      fn: "export_customer_inventory_snapshot",
      args: {
        p_tenant_id: TENANT_ID,
        p_actor_auth_user_id: ACTOR_ID,
        p_warehouse_id: WAREHOUSE_ID,
        p_item_master_id: ITEM_ID,
        p_limit: 500,
        p_actor_label: null,
      },
    });
  });

  test("forwards a caller-supplied limit and actorLabel", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await exportCustomerInventorySnapshot(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, limit: 100, actorLabel: "customer-alpha" });
    assert.equal(calls[0]?.args.p_limit, 100);
    assert.equal(calls[0]?.args.p_actor_label, "customer-alpha");
  });

  test("returns an empty array when zero rows match", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const result = await exportCustomerInventorySnapshot(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(result, []);
  });

  test("wraps an RPC error as CustomerInventoryAccessMutationError with mutation_failed for an unrecognized prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_error: boom" } });
    await assert.rejects(() => exportCustomerInventorySnapshot(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }), (err: unknown) => {
      assert.ok(err instanceof CustomerInventoryAccessMutationError);
      assert.equal(err.code, "mutation_failed");
      return true;
    });
  });

  test("rejects an invalid input shape before ever calling rpc", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(() => exportCustomerInventorySnapshot(client, { tenantId: "not-a-uuid", actorAuthUserId: ACTOR_ID }));
    assert.equal(calls.length, 0);
  });
});
