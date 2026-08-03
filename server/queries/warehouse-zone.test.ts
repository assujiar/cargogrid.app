import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listTenantWarehouses, listWarehouseZones, listWarehouseCustomerEligibility, getWarehouseDeactivationImpact, WarehouseZoneQueryError, type WarehouseZoneQueryClient } from "./warehouse-zone.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ORG_UNIT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: WarehouseZoneQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as WarehouseZoneQueryClient;
  return { client, calls };
}

describe("listTenantWarehouses", () => {
  test("maps rows and passes a null status filter by default", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: WAREHOUSE_ID,
          company_org_unit_id: ORG_UNIT_ID,
          code: "WH-JKT-1",
          name: "Jakarta DC 1",
          site_address: "Jl. Marunda Raya 1",
          timezone: "Asia/Jakarta",
          site_geog_geojson: { type: "Point", coordinates: [106.83, -6.18] },
          service_type_eligibility: ["land"],
          status: "active",
          zone_count: 4,
          active_zone_count: 3,
          record_version: 2,
          created_at: "2026-08-03T00:00:00.000Z",
          updated_at: "2026-08-03T01:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listTenantWarehouses(client, TENANT_ID, ACTOR_ID);
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.zoneCount, 4);
    assert.equal(calls[0]?.fn, "list_tenant_warehouses");
    assert.equal(calls[0]?.args.p_status_filter, null);
  });

  test("returns an empty array when no data is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const rows = await listTenantWarehouses(client, TENANT_ID, ACTOR_ID, "inactive");
    assert.deepEqual(rows, []);
  });

  test("throws WarehouseZoneQueryError on an rpc error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View" } });
    await assert.rejects(() => listTenantWarehouses(client, TENANT_ID, ACTOR_ID), WarehouseZoneQueryError);
  });
});

describe("listWarehouseZones", () => {
  test("maps zone rows filtered by status", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          id: "823e4567-e89b-12d3-a456-426614174000",
          tenant_id: TENANT_ID,
          warehouse_id: WAREHOUSE_ID,
          code: "COLD-A",
          name: "Cold Storage Zone A",
          zone_type: "cold_storage",
          environment: {},
          capacity_value: null,
          capacity_uom: null,
          restrictions: {},
          status: "inactive",
          effective_from: null,
          effective_to: null,
          record_version: 1,
          created_by: "rep",
          created_at: "2026-08-03T00:00:00.000Z",
          updated_at: "2026-08-03T00:00:00.000Z",
        },
      ],
      error: null,
    });
    const rows = await listWarehouseZones(client, WAREHOUSE_ID, ACTOR_ID, "inactive");
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.status, "inactive");
    assert.equal(calls[0]?.args.p_status_filter, "inactive");
  });
});

describe("listWarehouseCustomerEligibility", () => {
  test("maps eligibility rows joined to the account's legal_name", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
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
        },
      ],
      error: null,
    });
    const rows = await listWarehouseCustomerEligibility(client, WAREHOUSE_ID, ACTOR_ID);
    assert.equal(rows[0]?.customerLegalName, "WMS229 Customer Co");
  });
});

describe("getWarehouseDeactivationImpact", () => {
  test("maps the impact preview", async () => {
    const { client } = fakeRpcClient({ data: { active_zone_count: 2, on_hold_zone_count: 1, active_customer_eligibility_count: 0 }, error: null });
    const impact = await getWarehouseDeactivationImpact(client, WAREHOUSE_ID, ACTOR_ID);
    assert.equal(impact.activeZoneCount, 2);
    assert.equal(impact.onHoldZoneCount, 1);
  });

  test("throws WarehouseZoneQueryError when no row is returned", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    await assert.rejects(() => getWarehouseDeactivationImpact(client, WAREHOUSE_ID, ACTOR_ID), WarehouseZoneQueryError);
  });
});
