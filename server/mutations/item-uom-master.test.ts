import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { createItemMaster, updateItemMaster, setItemMasterStatus, ItemUomMasterMutationError, type ItemUomMasterMutationRpcClient } from "./item-uom-master.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: ItemUomMasterMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ItemUomMasterMutationRpcClient;
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

describe("createItemMaster", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [ITEM_ROW], error: null });
    const item = await createItemMaster(client, {
      tenantId: TENANT_ID,
      ownerAccountId: ACCOUNT_ID,
      code: "SKU-100",
      name: "Test Widget",
      description: null,
      baseUomCode: "PCS",
      lotControlled: false,
      serialControlled: false,
      expiryControlled: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(item.code, "SKU-100");
    assert.equal(calls[0]?.fn, "create_item_master");
    assert.equal(calls[0]?.args.p_owner_account_id, ACCOUNT_ID);
    assert.equal(calls[0]?.args.p_base_uom_code, "PCS");
  });

  test("classifies a known error prefix", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "owner_account_not_found: nope is not an active account" } });
    await assert.rejects(
      () =>
        createItemMaster(client, {
          tenantId: TENANT_ID,
          ownerAccountId: ACCOUNT_ID,
          code: "SKU-100",
          name: "Test Widget",
          description: null,
          baseUomCode: "PCS",
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "owner_account_not_found",
    );
  });

  test("classifies an unrecognized error prefix as mutation_failed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "some_unexpected_db_error: boom" } });
    await assert.rejects(
      () =>
        createItemMaster(client, {
          tenantId: TENANT_ID,
          ownerAccountId: ACCOUNT_ID,
          code: "SKU-100",
          name: "Test Widget",
          description: null,
          baseUomCode: "PCS",
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "mutation_failed",
    );
  });

  test("throws invalid_response when the RPC returns no row", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () =>
        createItemMaster(client, {
          tenantId: TENANT_ID,
          ownerAccountId: ACCOUNT_ID,
          code: "SKU-100",
          name: "Test Widget",
          description: null,
          baseUomCode: "PCS",
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "invalid_response",
    );
  });
});

describe("updateItemMaster", () => {
  test("sends the mapped RPC args (no code/owner/uom params exist -- immutable)", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ITEM_ROW, name: "Renamed", record_version: 2 }], error: null });
    const item = await updateItemMaster(client, {
      itemMasterId: ITEM_ID,
      name: "Renamed",
      description: "updated",
      lotControlled: true,
      serialControlled: false,
      expiryControlled: true,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(item.name, "Renamed");
    assert.equal(calls[0]?.fn, "update_item_master");
    assert.equal(calls[0]?.args.p_expected_version, 1);
    assert.equal("p_code" in (calls[0]?.args ?? {}), false);
  });

  test("classifies stale_version", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: item master x expected version 1 but found 2" } });
    await assert.rejects(
      () =>
        updateItemMaster(client, {
          itemMasterId: ITEM_ID,
          name: "Renamed",
          description: null,
          lotControlled: false,
          serialControlled: false,
          expiryControlled: false,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "stale_version",
    );
  });
});

describe("setItemMasterStatus", () => {
  test("sends the mapped RPC args and parses the response row", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ ...ITEM_ROW, status: "inactive", record_version: 2 }], error: null });
    const item = await setItemMasterStatus(client, {
      itemMasterId: ITEM_ID,
      newStatus: "inactive",
      reason: "discontinued",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(item.status, "inactive");
    assert.equal(calls[0]?.fn, "set_item_master_status");
    assert.equal(calls[0]?.args.p_reason, "discontinued");
  });

  test("classifies invalid_reason (deactivation requires a reason)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_reason: a reason is required to deactivate an item master" } });
    await assert.rejects(
      () =>
        setItemMasterStatus(client, {
          itemMasterId: ITEM_ID,
          newStatus: "inactive",
          reason: null,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (err: unknown) => err instanceof ItemUomMasterMutationError && err.code === "invalid_reason",
    );
  });
});
