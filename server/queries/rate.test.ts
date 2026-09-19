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
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): RateQueryTableClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.fn = fn;
      capture.calls.args = args;
      return response;
    },
  };
  return fake as unknown as RateQueryTableClient;
}

describe("listRateVersionsForMasterRecord", () => {
  test("calls list_rate_versions_for_master_record with master_record_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_RATE_VERSION_ROW], error: null }, capture);
    const versions = await listRateVersionsForMasterRecord(client, MASTER_RECORD_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_rate_versions_for_master_record");
    assert.deepEqual(capture.calls.args, { p_master_record_id: MASTER_RECORD_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(versions.length, 1);
    assert.equal(versions[0]?.vendorCode, "VENDOR-1");
  });
});

describe("getRateVersionById", () => {
  test("calls get_rate_version_by_id and returns null when not found", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);
    const version = await getRateVersionById(client, RATE_VERSION_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "get_rate_version_by_id");
    assert.deepEqual(capture.calls.args, { p_rate_version_id: RATE_VERSION_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(version, null);
  });

  test("wraps a query error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "boom" } }, { calls: {} });
    await assert.rejects(
      () => getRateVersionById(client, RATE_VERSION_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof RateQueryError);
        return true;
      },
    );
  });
});

describe("listPendingRateVersions", () => {
  test("calls list_pending_rate_versions with tenant_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [{ ...VALID_RATE_VERSION_ROW, approval_status: "pending_approval" }], error: null }, capture);
    const versions = await listPendingRateVersions(client, TENANT_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_pending_rate_versions");
    assert.deepEqual(capture.calls.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(versions[0]?.approvalStatus, "pending_approval");
  });
});

describe("listActiveVendorRates", () => {
  test("calls list_active_vendor_rates with tenant_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_RATE_VERSION_ROW], error: null }, capture);
    const versions = await listActiveVendorRates(client, TENANT_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_active_vendor_rates");
    assert.deepEqual(capture.calls.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(versions.length, 1);
  });
});

describe("listRateSelectionsForRequest", () => {
  test("calls list_rate_selections_for_request with costing_request_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_SELECTION_ROW], error: null }, capture);
    const selections = await listRateSelectionsForRequest(client, REQUEST_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_rate_selections_for_request");
    assert.deepEqual(capture.calls.args, { p_costing_request_id: REQUEST_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(selections[0]?.amount, 15000000);
  });
});
