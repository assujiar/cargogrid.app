import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createWarehouse,
  updateWarehouse,
  setWarehouseStatus,
  grantWarehouseCustomerEligibility,
  revokeWarehouseCustomerEligibility,
  createWarehouseZone,
  updateWarehouseZone,
  setWarehouseZoneStatus,
  WarehouseZoneMutationError,
  type WarehouseZoneMutationRpcClient,
} from "./warehouse-zone.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ORG_UNIT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";
const ZONE_ID = "823e4567-e89b-12d3-a456-426614174000";
const ELIGIBILITY_ID = "a23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WarehouseZoneMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WarehouseZoneMutationRpcClient;
  return { client, calls };
}

const WAREHOUSE_ROW = {
  id: WAREHOUSE_ID,
  tenant_id: TENANT_ID,
  company_org_unit_id: ORG_UNIT_ID,
  code: "WH-JKT-1",
  name: "Jakarta DC 1",
  site_address: "Jl. Marunda Raya 1",
  timezone: "Asia/Jakarta",
  service_type_eligibility: ["land"],
  status: "active",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const ZONE_ROW = {
  id: ZONE_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  code: "COLD-A",
  name: "Cold Storage Zone A",
  zone_type: "cold_storage",
  environment: {},
  capacity_value: null,
  capacity_uom: null,
  restrictions: {},
  status: "active",
  effective_from: null,
  effective_to: null,
  record_version: 1,
  created_by: "rep",
  created_at: "2026-08-03T00:00:00.000Z",
  updated_at: "2026-08-03T00:00:00.000Z",
};

const ELIGIBILITY_ROW = {
  id: ELIGIBILITY_ID,
  tenant_id: TENANT_ID,
  warehouse_id: WAREHOUSE_ID,
  customer_account_id: ACCOUNT_ID,
  status: "active",
  granted_by: "rep",
  granted_at: "2026-08-03T00:00:00.000Z",
  revoked_at: null,
  revoked_reason: null,
  record_version: 1,
};

describe("createWarehouse", () => {
  test("calls create_warehouse with snake_case args and never fabricates site_geog_geojson", async () => {
    const { client, calls } = fakeRpcClient({ data: WAREHOUSE_ROW, error: null });
    const warehouse = await createWarehouse(client, {
      tenantId: TENANT_ID,
      companyOrgUnitId: ORG_UNIT_ID,
      code: "WH-JKT-1",
      name: "Jakarta DC 1",
      siteAddress: "Jl. Marunda Raya 1",
      timezone: "Asia/Jakarta",
      siteGeojson: { type: "Point", coordinates: [106.8272, -6.1751] },
      serviceTypeEligibility: ["land"],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(warehouse.code, "WH-JKT-1");
    assert.equal(warehouse.siteGeojson, null);
    assert.equal(calls[0]?.fn, "create_warehouse");
    assert.equal(calls[0]?.args.p_company_org_unit_id, ORG_UNIT_ID);
    assert.deepEqual((calls[0]?.args.p_site_geojson as { coordinates: number[] }).coordinates, [106.8272, -6.1751]);
  });

  test("classifies a warehouse_code_conflict error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "warehouse_code_conflict: code WH-JKT-1 already exists for tenant under a different company org unit" } });
    await assert.rejects(
      () =>
        createWarehouse(client, {
          tenantId: TENANT_ID,
          companyOrgUnitId: ORG_UNIT_ID,
          code: "WH-JKT-1",
          name: "Jakarta DC 1",
          siteAddress: null,
          timezone: "Asia/Jakarta",
          siteGeojson: null,
          serviceTypeEligibility: [],
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof WarehouseZoneMutationError && error.code === "warehouse_code_conflict",
    );
  });
});

describe("updateWarehouse", () => {
  test("calls update_warehouse with snake_case args", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...WAREHOUSE_ROW, name: "Jakarta Distribution Center 1", record_version: 2 }, error: null });
    const warehouse = await updateWarehouse(client, {
      warehouseId: WAREHOUSE_ID,
      name: "Jakarta Distribution Center 1",
      siteAddress: "Jl. Marunda Raya 1A",
      timezone: "Asia/Makassar",
      siteGeojson: null,
      serviceTypeEligibility: ["land", "sea"],
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(warehouse.name, "Jakarta Distribution Center 1");
    assert.equal(calls[0]?.fn, "update_warehouse");
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });

  test("classifies a stale_version error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "stale_version: warehouse expected version 1 but found 2" } });
    await assert.rejects(
      () =>
        updateWarehouse(client, {
          warehouseId: WAREHOUSE_ID,
          name: "Jakarta DC 1",
          siteAddress: null,
          timezone: "Asia/Jakarta",
          siteGeojson: null,
          serviceTypeEligibility: [],
          expectedVersion: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof WarehouseZoneMutationError && error.code === "stale_version",
    );
  });
});

describe("setWarehouseStatus", () => {
  test("classifies a warehouse_has_active_zones error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "warehouse_has_active_zones: cannot be deactivated while 2 active/on-hold zone(s) exist" } });
    await assert.rejects(
      () => setWarehouseStatus(client, { warehouseId: WAREHOUSE_ID, newStatus: "inactive", reason: "wind down", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof WarehouseZoneMutationError && error.code === "warehouse_has_active_zones",
    );
  });

  test("deactivates once zones are wound down", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...WAREHOUSE_ROW, status: "inactive", record_version: 2 }, error: null });
    const warehouse = await setWarehouseStatus(client, { warehouseId: WAREHOUSE_ID, newStatus: "inactive", reason: "no longer needed", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(warehouse.status, "inactive");
    assert.equal(calls[0]?.args.p_reason, "no longer needed");
  });
});

describe("grantWarehouseCustomerEligibility / revokeWarehouseCustomerEligibility", () => {
  test("grants eligibility", async () => {
    const { client, calls } = fakeRpcClient({ data: ELIGIBILITY_ROW, error: null });
    const eligibility = await grantWarehouseCustomerEligibility(client, { warehouseId: WAREHOUSE_ID, customerAccountId: ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(eligibility.status, "active");
    assert.equal(calls[0]?.fn, "grant_warehouse_customer_eligibility");
  });

  test("classifies a reason_required error on revoke", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: a non-empty reason is required to revoke warehouse customer eligibility" } });
    await assert.rejects(
      () => revokeWarehouseCustomerEligibility(client, { id: ELIGIBILITY_ID, reason: "x", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof WarehouseZoneMutationError && error.code === "reason_required",
    );
  });

  test("revokes eligibility with a reason", async () => {
    const { client } = fakeRpcClient({ data: { ...ELIGIBILITY_ROW, status: "revoked", revoked_at: "2026-08-04T00:00:00.000Z", revoked_reason: "no longer eligible", record_version: 2 }, error: null });
    const eligibility = await revokeWarehouseCustomerEligibility(client, { id: ELIGIBILITY_ID, reason: "no longer eligible", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(eligibility.status, "revoked");
    assert.equal(eligibility.revokedReason, "no longer eligible");
  });
});

describe("createWarehouseZone / updateWarehouseZone / setWarehouseZoneStatus", () => {
  test("creates a zone", async () => {
    const { client, calls } = fakeRpcClient({ data: ZONE_ROW, error: null });
    const zone = await createWarehouseZone(client, {
      warehouseId: WAREHOUSE_ID,
      code: "COLD-A",
      name: "Cold Storage Zone A",
      zoneType: "cold_storage",
      environment: null,
      capacityValue: null,
      capacityUom: null,
      restrictions: null,
      effectiveFrom: null,
      effectiveTo: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(zone.zoneType, "cold_storage");
    assert.equal(calls[0]?.fn, "create_warehouse_zone");
  });

  test("classifies an invalid_capacity error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_capacity: capacity_value and capacity_uom must both be provided or both be omitted" } });
    await assert.rejects(
      () =>
        createWarehouseZone(client, {
          warehouseId: WAREHOUSE_ID,
          code: "BAD",
          name: "Bad",
          zoneType: "ambient",
          environment: null,
          capacityValue: 100,
          capacityUom: null,
          restrictions: null,
          effectiveFrom: null,
          effectiveTo: null,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "rep",
        }),
      (error: unknown) => error instanceof WarehouseZoneMutationError && error.code === "invalid_capacity",
    );
  });

  test("updates a zone", async () => {
    const { client } = fakeRpcClient({ data: { ...ZONE_ROW, name: "Cold Storage Zone A (expanded)", capacity_value: 750, capacity_uom: "pallet_position", record_version: 2 }, error: null });
    const zone = await updateWarehouseZone(client, {
      zoneId: ZONE_ID,
      name: "Cold Storage Zone A (expanded)",
      environment: null,
      capacityValue: 750,
      capacityUom: "pallet_position",
      restrictions: null,
      effectiveFrom: null,
      effectiveTo: null,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(zone.capacityValue, 750);
  });

  test("classifies a reason_required error when setting on_hold without a reason", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "reason_required: a non-empty reason is required to set a zone to on_hold" } });
    await assert.rejects(
      () => setWarehouseZoneStatus(client, { zoneId: ZONE_ID, newStatus: "on_hold", reason: null, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (error: unknown) => error instanceof WarehouseZoneMutationError && error.code === "reason_required",
    );
  });

  test("sets a zone on_hold with a reason", async () => {
    const { client } = fakeRpcClient({ data: { ...ZONE_ROW, status: "on_hold", record_version: 2 }, error: null });
    const zone = await setWarehouseZoneStatus(client, { zoneId: ZONE_ID, newStatus: "on_hold", reason: "temporary maintenance freeze", expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(zone.status, "on_hold");
  });
});
