import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWarehouseLocation,
  parseWarehouseLocationDeactivationImpact,
  CreateWarehouseLocationInputSchema,
  UpdateWarehouseLocationInputSchema,
} from "./bin-racking.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ZONE_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const RACK_ID = "723e4567-e89b-12d3-a456-426614174000";
const SHELF_ID = "823e4567-e89b-12d3-a456-426614174000";

describe("parseWarehouseLocation", () => {
  test("maps a root rack with no zone/parent", () => {
    const location = parseWarehouseLocation({
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
    });
    assert.equal(location.locationType, "rack");
    assert.equal(location.depth, 0);
    assert.deepEqual(location.path, []);
    assert.equal(location.zoneId, null);
  });

  test("maps a nested bin with a full path/capacity", () => {
    const location = parseWarehouseLocation({
      id: "923e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      zone_id: ZONE_ID,
      parent_id: SHELF_ID,
      code: "BIN-A1-1",
      name: "Bin A1-1",
      location_type: "bin",
      path: [RACK_ID, SHELF_ID],
      depth: 2,
      sequence: 1,
      capacity_value: "50",
      capacity_uom: "units",
      environment: {},
      restrictions: {},
      barcode: "BC-BIN-A1-1",
      pick_enabled: true,
      putaway_enabled: true,
      status: "draft",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(location.depth, 2);
    assert.deepEqual(location.path, [RACK_ID, SHELF_ID]);
    assert.equal(location.capacityValue, 50);
    assert.equal(location.pickEnabled, true);
  });
});

describe("parseWarehouseLocationDeactivationImpact", () => {
  test("maps a non-zero impact preview", () => {
    const impact = parseWarehouseLocationDeactivationImpact({ active_child_count: 1, draft_child_count: 2 });
    assert.equal(impact.activeChildCount, 1);
    assert.equal(impact.draftChildCount, 2);
  });
});

describe("CreateWarehouseLocationInputSchema", () => {
  test("accepts a valid root-level input", () => {
    const parsed = CreateWarehouseLocationInputSchema.parse({
      warehouseId: WAREHOUSE_ID,
      zoneId: ZONE_ID,
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
    assert.equal(parsed.locationType, "rack");
  });

  test("rejects an invalid location type", () => {
    assert.throws(() =>
      CreateWarehouseLocationInputSchema.parse({
        warehouseId: WAREHOUSE_ID,
        zoneId: null,
        parentId: null,
        code: "X",
        name: "X",
        locationType: "aisle",
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
    );
  });

  test("rejects an empty code", () => {
    assert.throws(() =>
      CreateWarehouseLocationInputSchema.parse({
        warehouseId: WAREHOUSE_ID,
        zoneId: null,
        parentId: null,
        code: "",
        name: "Rack A",
        locationType: "rack",
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
    );
  });
});

describe("UpdateWarehouseLocationInputSchema", () => {
  test("rejects a negative capacity value", () => {
    assert.throws(() =>
      UpdateWarehouseLocationInputSchema.parse({
        locationId: RACK_ID,
        name: "Rack A",
        sequence: 1,
        capacityValue: -1,
        capacityUom: "units",
        environment: null,
        restrictions: null,
        barcode: null,
        pickEnabled: false,
        putawayEnabled: false,
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
