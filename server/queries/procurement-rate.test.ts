import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listVendorRateTiers,
  listVendorRateVersionsForVendor,
  listProcurementLinkedVendorRateVersions,
  ProcurementRateQueryError,
  type ProcurementRateQueryTableClient,
} from "./procurement-rate.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RATE_VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const TIER_ID = "423e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "523e4567-e89b-12d3-a456-426614174000";

const VALID_TIER_ROW = {
  id: TIER_ID,
  tenant_id: TENANT_ID,
  rate_version_id: RATE_VERSION_ID,
  tier_order: 1,
  weight_min: 0,
  weight_max: 100,
  volume_min: 0,
  volume_max: null,
  amount: 500000,
  minimum_charge: null,
  cost_masked: false,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): ProcurementRateQueryTableClient {
  function chain(): Record<string, unknown> {
    return {
      eq(column: string, value: unknown) {
        const eqCalls = (capture.calls.eqCalls ?? []) as { column: string; value: unknown }[];
        eqCalls.push({ column, value });
        capture.calls.eqCalls = eqCalls;
        return chain();
      },
      not(column: string, operator: string, value: unknown) {
        capture.calls.notCall = { column, operator, value };
        return chain();
      },
      order(column: string, opts: { ascending: boolean }) {
        capture.calls.orderColumn = column;
        capture.calls.ascending = opts.ascending;
        // Some callers (listVendorRateTiers) await the result of .order() directly
        // (unbounded is fine there -- one rate version's own tier count); others
        // (listProcurementLinkedVendorRateVersions, listVendorRateVersionsForVendor,
        // post-review fix) chain a further .limit() call. Spreading `response`'s own
        // fields onto the returned object supports both: destructuring
        // {data, error} works whether or not .limit() is called afterward.
        return {
          ...response,
          limit(count: number) {
            capture.calls.limitCount = count;
            return response;
          },
        };
      },
    };
  }

  const fake = {
    from(table: string) {
      capture.calls.table = table;
      return { select: () => chain() };
    },
  };
  return fake as unknown as ProcurementRateQueryTableClient;
}

describe("listVendorRateTiers", () => {
  test("queries the field-masked vendor_rate_tiers_directory view, filtered by rate_version_id, ordered by tier_order", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_TIER_ROW], error: null }, capture);

    const tiers = await listVendorRateTiers(client, RATE_VERSION_ID);

    assert.equal(capture.calls.table, "vendor_rate_tiers_directory");
    assert.deepEqual(capture.calls.eqCalls, [{ column: "rate_version_id", value: RATE_VERSION_ID }]);
    assert.equal(capture.calls.orderColumn, "tier_order");
    assert.equal(capture.calls.ascending, true);
    assert.equal(tiers.length, 1);
    assert.equal(tiers[0]?.id, TIER_ID);
    assert.equal(tiers[0]?.amount, 500000);
  });

  test("returns an empty array (not an error) when zero rows match", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: null, error: null }, capture);
    const tiers = await listVendorRateTiers(client, RATE_VERSION_ID);
    assert.deepEqual(tiers, []);
  });

  test("throws ProcurementRateQueryError on a real error", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: null, error: { message: "permission denied" } }, capture);
    await assert.rejects(() => listVendorRateTiers(client, RATE_VERSION_ID), ProcurementRateQueryError);
  });
});

describe("listProcurementLinkedVendorRateVersions", () => {
  test("filters to tenant_id and non-null vendor_master_id, newest first", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);

    await listProcurementLinkedVendorRateVersions(client, TENANT_ID);

    assert.equal(capture.calls.table, "vendor_rate_versions_directory");
    assert.deepEqual(capture.calls.eqCalls, [{ column: "tenant_id", value: TENANT_ID }]);
    assert.deepEqual(capture.calls.notCall, { column: "vendor_master_id", operator: "is", value: null });
    assert.equal(capture.calls.orderColumn, "created_at");
    assert.equal(capture.calls.ascending, false);
    // Post-review fix (§17 "no unbounded browser-loaded dataset"): the query is
    // now bounded by a hard LIMIT.
    assert.equal(capture.calls.limitCount, 200);
  });
});

describe("listVendorRateVersionsForVendor", () => {
  test("queries vendor_rate_versions_directory filtered by tenant_id and vendor_master_id, newest first", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);

    await listVendorRateVersionsForVendor(client, TENANT_ID, VENDOR_MASTER_ID);

    assert.equal(capture.calls.table, "vendor_rate_versions_directory");
    assert.deepEqual(capture.calls.eqCalls, [
      { column: "tenant_id", value: TENANT_ID },
      { column: "vendor_master_id", value: VENDOR_MASTER_ID },
    ]);
    assert.equal(capture.calls.orderColumn, "created_at");
    assert.equal(capture.calls.ascending, false);
    // Post-review fix (§17 "no unbounded browser-loaded dataset"): the query is
    // now bounded by a hard LIMIT.
    assert.equal(capture.calls.limitCount, 200);
  });
});
