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
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): ProcurementRateQueryTableClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.fn = fn;
      capture.calls.args = args;
      return response;
    },
  };
  return fake as unknown as ProcurementRateQueryTableClient;
}

describe("listVendorRateTiers", () => {
  test("calls list_vendor_rate_tiers with rate_version_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [VALID_TIER_ROW], error: null }, capture);

    const tiers = await listVendorRateTiers(client, RATE_VERSION_ID, ACTOR_ID);

    assert.equal(capture.calls.fn, "list_vendor_rate_tiers");
    assert.deepEqual(capture.calls.args, { p_rate_version_id: RATE_VERSION_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(tiers.length, 1);
    assert.equal(tiers[0]?.id, TIER_ID);
    assert.equal(tiers[0]?.amount, 500000);
  });

  test("returns an empty array (not an error) when zero rows match", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: null, error: null }, capture);
    const tiers = await listVendorRateTiers(client, RATE_VERSION_ID, ACTOR_ID);
    assert.deepEqual(tiers, []);
  });

  test("throws ProcurementRateQueryError on a real error", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: null, error: { message: "permission denied" } }, capture);
    await assert.rejects(() => listVendorRateTiers(client, RATE_VERSION_ID, ACTOR_ID), ProcurementRateQueryError);
  });
});

describe("listProcurementLinkedVendorRateVersions", () => {
  test("calls list_procurement_linked_vendor_rate_versions with tenant_id/actor/limit", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);

    await listProcurementLinkedVendorRateVersions(client, TENANT_ID, ACTOR_ID);

    assert.equal(capture.calls.fn, "list_procurement_linked_vendor_rate_versions");
    // Post-review fix (§17 "no unbounded browser-loaded dataset"): the query is
    // now bounded by a hard LIMIT, applied server-side by the RPC.
    assert.deepEqual(capture.calls.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_limit: 200 });
  });
});

describe("listVendorRateVersionsForVendor", () => {
  test("calls list_vendor_rate_versions_for_vendor with tenant_id/vendor_master_id/actor/limit", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);

    await listVendorRateVersionsForVendor(client, TENANT_ID, VENDOR_MASTER_ID, ACTOR_ID);

    assert.equal(capture.calls.fn, "list_vendor_rate_versions_for_vendor");
    // Post-review fix (§17 "no unbounded browser-loaded dataset"): the query is
    // now bounded by a hard LIMIT, applied server-side by the RPC.
    assert.deepEqual(capture.calls.args, { p_tenant_id: TENANT_ID, p_vendor_master_id: VENDOR_MASTER_ID, p_actor_auth_user_id: ACTOR_ID, p_limit: 200 });
  });
});
