import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getVendorComparison, listVendorComparisons, listVendorComparisonOffers, VendorComparisonQueryError, type VendorComparisonQueryRpcClient } from "./vendor-comparison.ts";

const COMPARISON_ID = "323e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "823e4567-e89b-12d3-a456-426614174000";

const VALID_COMPARISON_ROW = {
  id: COMPARISON_ID,
  tenant_id: TENANT_ID,
  org_unit_id: null,
  rfq_id: "423e4567-e89b-12d3-a456-426614174000",
  sourcing_request_id: "523e4567-e89b-12d3-a456-426614174000",
  version: 1,
  revised_from_id: null,
  comparison_currency: "IDR",
  basis_weight: 5000,
  basis_volume: null,
  basis_quantity: 1,
  criteria_snapshot: [{ key: "price", label: "Price", weight: 100 }],
  status: "draft",
  recommended_offer_id: null,
  recommended_reason: null,
  recommended_at: null,
  selected_offer_id: null,
  selection_reason: null,
  submitted_at: null,
  submitted_by: null,
  idempotency_key: "idem-1",
  record_version: 1,
  created_by: "tester",
  created_at: "2026-08-01T00:00:00.000Z",
  updated_at: "2026-08-01T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): VendorComparisonQueryRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as VendorComparisonQueryRpcClient;
}

describe("getVendorComparison", () => {
  test("calls get_vendor_comparison with p_comparison_id/p_actor_auth_user_id and parses the row", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_COMPARISON_ROW, error: null }, calls);

    const comparison = await getVendorComparison(client, COMPARISON_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "get_vendor_comparison");
    assert.equal(calls[0]?.args.p_comparison_id, COMPARISON_ID);
    assert.equal(calls[0]?.args.p_actor_auth_user_id, ACTOR_ID);
    assert.equal(comparison.id, COMPARISON_ID);
  });

  test("throws VendorComparisonQueryError on a vendor_comparison_not_found error", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "vendor_comparison_not_found: 323e4567-e89b-12d3-a456-426614174000" } }, []);
    await assert.rejects(
      () => getVendorComparison(client, COMPARISON_ID, ACTOR_ID),
      (err: unknown) => {
        assert.ok(err instanceof VendorComparisonQueryError);
        return true;
      },
    );
  });

  test("throws VendorComparisonQueryError when the RPC returns no row and no error", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    await assert.rejects(() => getVendorComparison(client, COMPARISON_ID, ACTOR_ID));
  });
});

describe("listVendorComparisons", () => {
  test("passes tenantId/rfqId/status/limit through as p_ params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_COMPARISON_ROW], error: null }, calls);

    const rows = await listVendorComparisons(client, TENANT_ID, ACTOR_ID, "423e4567-e89b-12d3-a456-426614174000", "draft", 25);

    assert.equal(calls[0]?.fn, "list_vendor_comparisons");
    assert.equal(calls[0]?.args.p_tenant_id, TENANT_ID);
    assert.equal(calls[0]?.args.p_rfq_id, "423e4567-e89b-12d3-a456-426614174000");
    assert.equal(calls[0]?.args.p_status, "draft");
    assert.equal(calls[0]?.args.p_limit, 25);
    assert.equal(rows.length, 1);
  });

  test("returns an empty array when data is null", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    const rows = await listVendorComparisons(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(rows, []);
  });
});

describe("listVendorComparisonOffers", () => {
  test("calls list_vendor_comparison_offers with p_comparison_id/p_actor_auth_user_id", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [], error: null }, calls);

    await listVendorComparisonOffers(client, COMPARISON_ID, ACTOR_ID);

    assert.equal(calls[0]?.fn, "list_vendor_comparison_offers");
    assert.equal(calls[0]?.args.p_comparison_id, COMPARISON_ID);
  });
});
