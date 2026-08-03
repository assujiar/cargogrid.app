import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWarehouse,
  parseWarehouseZone,
  parseWarehouseCustomerEligibility,
  parseTenantWarehouseListRow,
  parseWarehouseCustomerEligibilityListRow,
  parseWarehouseDeactivationImpact,
  CreateWarehouseInputSchema,
  CreateWarehouseZoneInputSchema,
} from "./warehouse-zone.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ORG_UNIT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseWarehouse", () => {
  test("maps an active warehouse row with a site_geog_geojson point", () => {
    const warehouse = parseWarehouse({
      id: WAREHOUSE_ID,
      tenant_id: TENANT_ID,
      company_org_unit_id: ORG_UNIT_ID,
      code: "WH-JKT-1",
      name: "Jakarta DC 1",
      site_address: "Jl. Marunda Raya 1",
      timezone: "Asia/Jakarta",
      site_geog_geojson: { type: "Point", coordinates: [106.8272, -6.1751] },
      service_type_eligibility: ["land"],
      status: "active",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(warehouse.code, "WH-JKT-1");
    assert.deepEqual(warehouse.siteGeojson, { type: "Point", coordinates: [106.8272, -6.1751] });
    assert.deepEqual(warehouse.serviceTypeEligibility, ["land"]);
  });

  test("maps a mutation response honestly nulling site_geog_geojson (never fabricated from a raw geography column)", () => {
    const warehouse = parseWarehouse({
      id: WAREHOUSE_ID,
      tenant_id: TENANT_ID,
      company_org_unit_id: ORG_UNIT_ID,
      code: "WH-JKT-2",
      name: "Jakarta DC 2",
      site_address: null,
      timezone: "Asia/Jakarta",
      site_geog_geojson: null,
      service_type_eligibility: [],
      status: "active",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(warehouse.siteGeojson, null);
    assert.deepEqual(warehouse.serviceTypeEligibility, []);
  });
});

describe("parseWarehouseZone", () => {
  test("maps a cold_storage zone with capacity and environment", () => {
    const zone = parseWarehouseZone({
      id: "823e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      code: "COLD-A",
      name: "Cold Storage Zone A",
      zone_type: "cold_storage",
      environment: { target_temp_c: -18 },
      capacity_value: "500",
      capacity_uom: "pallet_position",
      restrictions: {},
      status: "active",
      effective_from: null,
      effective_to: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(zone.zoneType, "cold_storage");
    assert.equal(zone.capacityValue, 500);
    assert.deepEqual(zone.environment, { target_temp_c: -18 });
  });

  test("maps a scheduled future zone (on_hold status, future effective_from)", () => {
    const zone = parseWarehouseZone({
      id: "923e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      code: "STAGING-B",
      name: "Future Staging Zone B",
      zone_type: "staging",
      environment: {},
      capacity_value: null,
      capacity_uom: null,
      restrictions: {},
      status: "on_hold",
      effective_from: "2026-09-02T00:00:00.000Z",
      effective_to: null,
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(zone.status, "on_hold");
    assert.equal(zone.effectiveFrom, "2026-09-02T00:00:00.000Z");
    assert.equal(zone.capacityValue, null);
  });
});

describe("parseWarehouseCustomerEligibility", () => {
  test("maps an active grant", () => {
    const row = parseWarehouseCustomerEligibility({
      id: "a23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      customer_account_id: ACCOUNT_ID,
      status: "active",
      granted_by: "rep",
      granted_at: "2026-08-03T00:00:00.000Z",
      revoked_at: null,
      revoked_reason: null,
      record_version: 1,
    });
    assert.equal(row.status, "active");
    assert.equal(row.revokedReason, null);
  });

  test("maps a revoked grant with a mandatory reason", () => {
    const row = parseWarehouseCustomerEligibility({
      id: "a23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      customer_account_id: ACCOUNT_ID,
      status: "revoked",
      granted_by: "rep",
      granted_at: "2026-08-03T00:00:00.000Z",
      revoked_at: "2026-08-04T00:00:00.000Z",
      revoked_reason: "account no longer eligible",
      record_version: 2,
    });
    assert.equal(row.status, "revoked");
    assert.equal(row.revokedReason, "account no longer eligible");
  });
});

describe("parseTenantWarehouseListRow", () => {
  test("maps a list row including zone_count/active_zone_count", () => {
    const row = parseTenantWarehouseListRow({
      id: WAREHOUSE_ID,
      company_org_unit_id: ORG_UNIT_ID,
      code: "WH-JKT-1",
      name: "Jakarta DC 1",
      site_address: "Jl. Marunda Raya 1",
      timezone: "Asia/Jakarta",
      site_geog_geojson: { type: "Point", coordinates: [106.83, -6.18] },
      service_type_eligibility: ["land", "sea"],
      status: "active",
      zone_count: 4,
      active_zone_count: 3,
      record_version: 2,
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T01:00:00.000Z",
    });
    assert.equal(row.zoneCount, 4);
    assert.equal(row.activeZoneCount, 3);
  });
});

describe("parseWarehouseCustomerEligibilityListRow", () => {
  test("maps a listed grant joined to the account's own legal_name", () => {
    const row = parseWarehouseCustomerEligibilityListRow({
      id: "a23e4567-e89b-12d3-a456-426614174000",
      warehouse_id: WAREHOUSE_ID,
      customer_account_id: ACCOUNT_ID,
      customer_legal_name: "WMS229 Customer Co",
      status: "active",
      granted_by: "rep",
      granted_at: "2026-08-03T00:00:00.000Z",
      revoked_at: null,
      revoked_reason: null,
      record_version: 1,
    });
    assert.equal(row.customerLegalName, "WMS229 Customer Co");
  });
});

describe("parseWarehouseDeactivationImpact", () => {
  test("maps a non-zero impact preview", () => {
    const impact = parseWarehouseDeactivationImpact({ active_zone_count: 2, on_hold_zone_count: 1, active_customer_eligibility_count: 3 });
    assert.equal(impact.activeZoneCount, 2);
    assert.equal(impact.onHoldZoneCount, 1);
    assert.equal(impact.activeCustomerEligibilityCount, 3);
  });
});

describe("CreateWarehouseInputSchema", () => {
  test("accepts a valid input with a site GeoJSON point", () => {
    const parsed = CreateWarehouseInputSchema.parse({
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
    assert.equal(parsed.code, "WH-JKT-1");
  });

  test("rejects an empty code", () => {
    assert.throws(() =>
      CreateWarehouseInputSchema.parse({
        tenantId: TENANT_ID,
        companyOrgUnitId: ORG_UNIT_ID,
        code: "",
        name: "Jakarta DC 1",
        siteAddress: null,
        timezone: "Asia/Jakarta",
        siteGeojson: null,
        serviceTypeEligibility: [],
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("CreateWarehouseZoneInputSchema", () => {
  test("accepts a valid input with capacity value+uom together", () => {
    const parsed = CreateWarehouseZoneInputSchema.parse({
      warehouseId: WAREHOUSE_ID,
      code: "COLD-A",
      name: "Cold Storage Zone A",
      zoneType: "cold_storage",
      environment: { target_temp_c: -18 },
      capacityValue: 500,
      capacityUom: "pallet_position",
      restrictions: null,
      effectiveFrom: null,
      effectiveTo: null,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.capacityValue, 500);
  });

  test("rejects a negative capacity value", () => {
    assert.throws(() =>
      CreateWarehouseZoneInputSchema.parse({
        warehouseId: WAREHOUSE_ID,
        code: "COLD-A",
        name: "Cold Storage Zone A",
        zoneType: "cold_storage",
        environment: null,
        capacityValue: -1,
        capacityUom: "pallet_position",
        restrictions: null,
        effectiveFrom: null,
        effectiveTo: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects an empty zone_type", () => {
    assert.throws(() =>
      CreateWarehouseZoneInputSchema.parse({
        warehouseId: WAREHOUSE_ID,
        code: "COLD-A",
        name: "Cold Storage Zone A",
        zoneType: "",
        environment: null,
        capacityValue: null,
        capacityUom: null,
        restrictions: null,
        effectiveFrom: null,
        effectiveTo: null,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
