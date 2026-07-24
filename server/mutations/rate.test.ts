import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createRateVersion,
  approveRateVersion,
  rejectRateVersion,
  withdrawRateVersion,
  searchVendorRates,
  selectVendorRate,
  RateMutationError,
  type RateMutationRpcClient,
} from "./rate.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RATE_VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const MASTER_RECORD_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "623e4567-e89b-12d3-a456-426614174000";
const SELECTION_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_RATE_VERSION_ROW = {
  id: RATE_VERSION_ID,
  tenant_id: TENANT_ID,
  master_record_id: MASTER_RECORD_ID,
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
  approval_status: "pending_approval",
  effective_from: "2026-07-24T00:00:00.000Z",
  effective_to: null,
  supersedes_version_id: null,
  approved_by: null,
  approved_at: null,
  rejected_reason: null,
  withdrawn_reason: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
  updated_at: "2026-07-24T00:00:00.000Z",
};

const VALID_DIRECTORY_ROW = {
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
  override_reason: null,
  selected_by: "tester",
  created_at: "2026-07-24T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): RateMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as RateMutationRpcClient;
}

describe("createRateVersion", () => {
  test("calls create_rate_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RATE_VERSION_ROW, error: null }, calls);

    const version = await createRateVersion(client, {
      tenantId: TENANT_ID,
      vendorCode: "VENDOR-1",
      vendorName: "Vendor One",
      serviceType: "ocean_freight",
      mode: "FCL",
      originLane: "Jakarta",
      destinationLane: "Surabaya",
      currency: "IDR",
      baseAmount: 15000000,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "create_rate_version");
    assert.equal(calls[0]?.args.p_vendor_code, "VENDOR-1");
    assert.equal(calls[0]?.args.p_base_amount, 15000000);
    assert.equal(calls[0]?.args.p_supersedes_version_id, null);
    assert.equal(version.id, RATE_VERSION_ID);
    assert.equal(version.approvalStatus, "pending_approval");
  });

  test("classifies insufficient_authority", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x holds neither Supreme Admin nor tenant_admin authority for tenant y" } }, []);
    await assert.rejects(
      () =>
        createRateVersion(client, {
          tenantId: TENANT_ID,
          vendorCode: "VENDOR-1",
          vendorName: "Vendor One",
          serviceType: "ocean_freight",
          originLane: "Jakarta",
          destinationLane: "Surabaya",
          currency: "IDR",
          baseAmount: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof RateMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("approveRateVersion", () => {
  test("calls approve_rate_version with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RATE_VERSION_ROW, approval_status: "approved" }, error: null }, calls);
    const version = await approveRateVersion(client, { rateVersionId: RATE_VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "approve_rate_version");
    assert.equal(calls[0]?.args.p_expected_version, 1);
    assert.equal(version.approvalStatus, "approved");
  });

  test("classifies stale_version", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "stale_version: rate version x expected version 1 but found 2" } }, []);
    await assert.rejects(
      () => approveRateVersion(client, { rateVersionId: RATE_VERSION_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RateMutationError);
        assert.equal(err.code, "stale_version");
        return true;
      },
    );
  });
});

describe("rejectRateVersion", () => {
  test("calls reject_rate_version with the mandatory reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RATE_VERSION_ROW, approval_status: "rejected", rejected_reason: "Pricing not competitive" }, error: null }, calls);
    const version = await rejectRateVersion(client, { rateVersionId: RATE_VERSION_ID, expectedVersion: 1, reason: "Pricing not competitive", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.args.p_reason, "Pricing not competitive");
    assert.equal(version.rejectedReason, "Pricing not competitive");
  });
});

describe("withdrawRateVersion", () => {
  test("calls withdraw_rate_version with the mandatory reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RATE_VERSION_ROW, approval_status: "withdrawn", withdrawn_reason: "no longer offered" }, error: null }, calls);
    const version = await withdrawRateVersion(client, { rateVersionId: RATE_VERSION_ID, expectedVersion: 2, reason: "no longer offered", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(calls[0]?.fn, "withdraw_rate_version");
    assert.equal(version.approvalStatus, "withdrawn");
  });
});

describe("searchVendorRates", () => {
  test("calls search_vendor_rates and maps every row through the directory contract", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_DIRECTORY_ROW], error: null }, calls);
    const results = await searchVendorRates(client, {
      tenantId: TENANT_ID,
      serviceType: "ocean_freight",
      originLane: "Jakarta",
      destinationLane: "Surabaya",
      actorAuthUserId: ACTOR_ID,
    });
    assert.equal(calls[0]?.fn, "search_vendor_rates");
    assert.equal(calls[0]?.args.p_limit, 20);
    assert.equal(results.length, 1);
    assert.equal(results[0]?.vendorCode, "VENDOR-1");
  });

  test("rejects a non-array response", async () => {
    const client = fakeRpcClient({ data: null, error: null }, []);
    await assert.rejects(
      () => searchVendorRates(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof RateMutationError);
        assert.equal(err.code, "invalid_response");
        return true;
      },
    );
  });
});

describe("selectVendorRate", () => {
  test("calls select_vendor_rate with the exact snake_case params for a non-adhoc selection", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_SELECTION_ROW, error: null }, calls);
    const selection = await selectVendorRate(client, {
      costingRequestId: REQUEST_ID,
      rateVersionId: RATE_VERSION_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(calls[0]?.fn, "select_vendor_rate");
    assert.equal(calls[0]?.args.p_is_adhoc, false);
    assert.equal(calls[0]?.args.p_rate_version_id, RATE_VERSION_ID);
    assert.equal(selection.isAdhoc, false);
    assert.equal(selection.amount, 15000000);
  });

  test("calls select_vendor_rate for an ad-hoc selection with the override reason", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_SELECTION_ROW, rate_version_id: null, is_adhoc: true, currency: "USD", amount: 999.5, override_reason: "Spot quote" }, error: null }, calls);
    const selection = await selectVendorRate(client, {
      costingRequestId: REQUEST_ID,
      isAdhoc: true,
      adhocCurrency: "USD",
      adhocAmount: 999.5,
      overrideReason: "Spot quote",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(calls[0]?.args.p_is_adhoc, true);
    assert.equal(calls[0]?.args.p_adhoc_currency, "USD");
    assert.equal(selection.isAdhoc, true);
    assert.equal(selection.overrideReason, "Spot quote");
  });

  test("classifies reason_required", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "reason_required: an ad-hoc rate selection requires a non-empty override reason" } }, []);
    await assert.rejects(
      () => selectVendorRate(client, { costingRequestId: REQUEST_ID, isAdhoc: true, adhocCurrency: "IDR", adhocAmount: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof RateMutationError);
        assert.equal(err.code, "reason_required");
        return true;
      },
    );
  });
});
