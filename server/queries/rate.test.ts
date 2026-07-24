import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listRateVersionsForMasterRecord,
  getRateVersionById,
  listPendingRateVersions,
  listActiveVendorRates,
  listRateSelectionsForRequest,
  RateQueryError,
  type RateQueryTableClient,
} from "./rate.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const MASTER_RECORD_ID = "323e4567-e89b-12d3-a456-426614174000";
const RATE_VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const SELECTION_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_RATE_VERSION_ROW = {
  rate_version_id: RATE_VERSION_ID,
  tenant_id: TENANT_ID,
  master_record_id: MASTER_RECORD_ID,
  vendor_code: "VENDOR-1",
  vendor_name: "Vendor One",
  service_type: "ocean_freight",
  mode: "FCL",
  origin_lane: "Jakarta",
  destination_lane: "Surabaya",
  equipment_type: null,
  cargo_weight_min: null,
  cargo_weight_max: null,
  cargo_volume_min: null,
  cargo_volume_max: null,
  currency: "IDR",
  base_amount: 15000000,
  minimum_amount: null,
  surcharge_components: [],
  cost_masked: false,
  approval_status: "approved",
  effective_from: "2026-07-24T00:00:00.000Z",
  effective_to: null,
  supersedes_version_id: null,
  approved_by: "tester",
  approved_at: "2026-07-24T00:00:00.000Z",
  rejected_reason: null,
  withdrawn_reason: null,
  record_version: 2,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

const VALID_SELECTION_ROW = {
  id: SELECTION_ID,
  tenant_id: TENANT_ID,
  costing_request_id: REQUEST_ID,
  rate_version_id: RATE_VERSION_ID,
  is_adhoc: false,
  currency: "IDR",
  amount: 15000000,
  snapshot: { id: RATE_VERSION_ID },
  cost_masked: false,
  override_reason: null,
  selected_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
};

function fakeTableClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): RateQueryTableClient {
  function chain(): Record<string, unknown> {
    return {
      eq(column: string, value: unknown) {
        const eqCalls = (capture.calls.eqCalls ?? []) as { column: string; value: unknown }[];
        eqCalls.push({ column, value });
        capture.calls.eqCalls = eqCalls;
        return chain();
      },
      order(column: string, opts: { ascending: boolean }) {
        capture.calls.orderColumn = column;
        capture.calls.ascending = opts.ascending;
        return response;
      },
      async maybeSingle() {
        const row = Array.isArray(response.data) ? (response.data[0] ?? null) : response.data;
        return { data: row, error: response.error };
      },
    };
  }

  const fake = {
    from(table: string) {
      capture.calls.table = table;
      return { select: () => chain() };
    },
  };
  return fake as unknown as RateQueryTableClient;
}

describe("listRateVersionsForMasterRecord", () => {
  test("queries the field-masked vendor_rate_versions_directory view, filtered by master_record_id, newest first", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_RATE_VERSION_ROW], error: null }, capture);
    const versions = await listRateVersionsForMasterRecord(client, MASTER_RECORD_ID);
    assert.equal(capture.calls.table, "vendor_rate_versions_directory");
    assert.equal(capture.calls.ascending, false);
    assert.equal(versions.length, 1);
    assert.equal(versions[0]?.vendorCode, "VENDOR-1");
  });
});

describe("getRateVersionById", () => {
  test("returns null (never an error) when RLS/no-match yields zero rows", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [], error: null }, capture);
    const version = await getRateVersionById(client, RATE_VERSION_ID);
    assert.equal(version, null);
  });

  test("wraps a query error", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: null, error: { message: "boom" } }, capture);
    await assert.rejects(
      () => getRateVersionById(client, RATE_VERSION_ID),
      (err: unknown) => {
        assert.ok(err instanceof RateQueryError);
        return true;
      },
    );
  });
});

describe("listPendingRateVersions", () => {
  test("filters by tenant_id and approval_status=pending_approval", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [{ ...VALID_RATE_VERSION_ROW, approval_status: "pending_approval" }], error: null }, capture);
    const versions = await listPendingRateVersions(client, TENANT_ID);
    const eqCalls = capture.calls.eqCalls as { column: string; value: unknown }[];
    assert.deepEqual(eqCalls, [
      { column: "tenant_id", value: TENANT_ID },
      { column: "approval_status", value: "pending_approval" },
    ]);
    assert.equal(versions[0]?.approvalStatus, "pending_approval");
  });
});

describe("listActiveVendorRates", () => {
  test("queries app.v_active_vendor_rates, filtered by tenant_id", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_RATE_VERSION_ROW], error: null }, capture);
    const versions = await listActiveVendorRates(client, TENANT_ID);
    assert.equal(capture.calls.table, "v_active_vendor_rates");
    assert.equal(versions.length, 1);
  });
});

describe("listRateSelectionsForRequest", () => {
  test("queries the field-masked rate_selections_directory view", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeTableClient({ data: [VALID_SELECTION_ROW], error: null }, capture);
    const selections = await listRateSelectionsForRequest(client, REQUEST_ID);
    assert.equal(capture.calls.table, "rate_selections_directory");
    assert.equal(selections[0]?.amount, 15000000);
  });
});
