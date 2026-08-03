import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createWarehouseLocation,
  updateWarehouseLocation,
  moveWarehouseLocation,
  setWarehouseLocationStatus,
  BinRackingMutationError,
  type BinRackingMutationRpcClient,
} from "./bin-racking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const RACK_ID = "723e4567-e89b-12d3-a456-426614174000";
const SHELF_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: BinRackingMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as BinRackingMutationRpcClient;
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

describe("createWarehouseLocation", () => {
  test("calls create_warehouse_location with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: RACK_ROW, error: null });
    const location = await createWarehouseLocation(client, {
      warehouseId: WAREHOUSE_ID,
      zoneId: null,
      parentId: null,
      code: "RACK-A",
      name: "Rack A",
      locationType: "rack",
      sequence: 1,
      capacityValue: null,
      capacityUom: null,
      environment: null,
      restrictions: null,
      barcode: "BC-RACK-A",
      pickEnabled: false,
      putawayEnabled: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(location.code, "RACK-A");
    assert.equal(calls[0]?.fn, "create_warehouse_location");
    assert.equal(calls[0]?.args.p_location_type, "rack");
  });

  test("classifies a location_code_conflict error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "location_code_conflict: code RACK-A already exists for warehouse with a different type/parent" } });
    await assert.rejects(
      () =>
        createWarehouseLocation(client, {
          warehouseId: WAREHOUSE_ID,
          zoneId: null,
          parentId: null,
          code: "RACK-A",
          name: "Rack A",
          locationType: "shelf",
          sequence: 1,
          capacityValue: null,
          capacityUom: null,
          environment: null,
          restrictions: null,
          barcode: null,
          pickEnabled: false,
          putawayEnabled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof BinRackingMutationError && error.code === "location_code_conflict",
    );
  });

  test("classifies a warehouse_location_depth_exceeded error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "warehouse_location_depth_exceeded: moving/creating under a node would exceed the governed maximum depth of 8" } });
    await assert.rejects(
      () =>
        createWarehouseLocation(client, {
          warehouseId: WAREHOUSE_ID,
          zoneId: null,
          parentId: SHELF_ID,
          code: "DEEP-9",
          name: "Deep 9",
          locationType: "bin",
          sequence: 1,
          capacityValue: null,
          capacityUom: null,
          environment: null,
          restrictions: null,
          barcode: null,
          pickEnabled: false,
          putawayEnabled: false,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof BinRackingMutationError && error.code === "warehouse_location_depth_exceeded",
    );
  });
});

describe("updateWarehouseLocation", () => {
  test("classifies a duplicate_barcode error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "duplicate_barcode: barcode BC-RACK-A is already assigned within this tenant" } });
    await assert.rejects(
      () =>
        updateWarehouseLocation(client, {
          locationId: SHELF_ID,
          name: "Shelf A1",
          sequence: 1,
          capacityValue: null,
          capacityUom: null,
          environment: null,
          restrictions: null,
          barcode: "BC-RACK-A",
          pickEnabled: false,
          putawayEnabled: false,
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof BinRackingMutationError && error.code === "duplicate_barcode",
    );
  });
});

describe("moveWarehouseLocation", () => {
  test("classifies a location_not_draft error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "location_not_draft: is active -- only a draft (empty, unused) location may be moved" } });
    await assert.rejects(
      () => moveWarehouseLocation(client, { locationId: RACK_ID, newParentId: SHELF_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof BinRackingMutationError && error.code === "location_not_draft",
    );
  });

  test("classifies a warehouse_location_cycle error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "warehouse_location_cycle: cannot be moved under its own descendant" } });
    await assert.rejects(
      () => moveWarehouseLocation(client, { locationId: RACK_ID, newParentId: SHELF_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof BinRackingMutationError && error.code === "warehouse_location_cycle",
    );
  });

  test("moves a draft location successfully", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...RACK_ROW, parent_id: SHELF_ID, depth: 1, path: [SHELF_ID], record_version: 2 }, error: null });
    const location = await moveWarehouseLocation(client, { locationId: RACK_ID, newParentId: SHELF_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(location.parentId, SHELF_ID);
    assert.equal(location.depth, 1);
    assert.equal(calls[0]?.args.p_new_parent_id, SHELF_ID);
  });
});

describe("setWarehouseLocationStatus", () => {
  test("classifies a location_has_active_children error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "location_has_active_children: cannot be deactivated while 1 draft/active child location(s) exist" } });
    await assert.rejects(
      () => setWarehouseLocationStatus(client, { locationId: RACK_ID, newStatus: "inactive", reason: "wind down", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof BinRackingMutationError && error.code === "location_has_active_children",
    );
  });

  test("activates a location", async () => {
    const { client } = fakeRpcClient({ data: { ...RACK_ROW, status: "active", record_version: 2 }, error: null });
    const location = await setWarehouseLocationStatus(client, { locationId: RACK_ID, newStatus: "active", reason: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(location.status, "active");
  });
});
