import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  CreateRateVersionInputSchema,
  SelectVendorRateInputSchema,
  SearchVendorRatesInputSchema,
  parseRateVersion,
  parseRateSelection,
} from "./rate.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RATE_VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const MASTER_RECORD_ID = "423e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("CreateRateVersionInputSchema", () => {
  test("defaults optional fields to null/empty", () => {
    const parsed = CreateRateVersionInputSchema.parse({
      tenantId: TENANT_ID,
      vendorCode: "VENDOR-1",
      vendorName: "Vendor One",
      serviceType: "ocean_freight",
      originLane: "Jakarta",
      destinationLane: "Surabaya",
      currency: "IDR",
      baseAmount: 15000000,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.mode, null);
    assert.equal(parsed.supersedesVersionId, null);
    assert.deepEqual(parsed.surchargeComponents, []);
  });

  test("rejects a malformed currency code", () => {
    assert.throws(() =>
      CreateRateVersionInputSchema.parse({
        tenantId: TENANT_ID,
        vendorCode: "VENDOR-1",
        vendorName: "Vendor One",
        serviceType: "ocean_freight",
        originLane: "Jakarta",
        destinationLane: "Surabaya",
        currency: "idr",
        baseAmount: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });

  test("rejects a negative base amount", () => {
    assert.throws(() =>
      CreateRateVersionInputSchema.parse({
        tenantId: TENANT_ID,
        vendorCode: "VENDOR-1",
        vendorName: "Vendor One",
        serviceType: "ocean_freight",
        originLane: "Jakarta",
        destinationLane: "Surabaya",
        currency: "IDR",
        baseAmount: -1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("SearchVendorRatesInputSchema", () => {
  test("defaults lane/service filters to null and limit to 20", () => {
    const parsed = SearchVendorRatesInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(parsed.serviceType, null);
    assert.equal(parsed.limit, 20);
  });

  test("rejects a limit above 200", () => {
    assert.throws(() => SearchVendorRatesInputSchema.parse({ tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID, limit: 201 }));
  });
});

describe("SelectVendorRateInputSchema", () => {
  test("defaults isAdhoc to false and adhoc fields to null", () => {
    const parsed = SelectVendorRateInputSchema.parse({ costingRequestId: REQUEST_ID, rateVersionId: RATE_VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(parsed.isAdhoc, false);
    assert.equal(parsed.adhocCurrency, null);
  });

  test("rejects a malformed ad-hoc currency code", () => {
    assert.throws(() =>
      SelectVendorRateInputSchema.parse({
        costingRequestId: REQUEST_ID,
        isAdhoc: true,
        adhocCurrency: "usd",
        adhocAmount: 1,
        overrideReason: "spot quote",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "tester",
      }),
    );
  });
});

describe("parseRateVersion", () => {
  test("maps a raw app.vendor_rate_versions_directory row to the camelCase contract shape", () => {
    const version = parseRateVersion({
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
      currency: null,
      base_amount: null,
      minimum_amount: null,
      surcharge_components: null,
      cost_masked: true,
      approval_status: "approved",
      effective_from: "2026-07-24T00:00:00.000Z",
      effective_to: null,
      supersedes_version_id: null,
      approved_by: "tester",
      approved_at: "2026-07-24T00:00:00.000Z",
      rejected_reason: null,
      withdrawn_reason: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
      updated_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(version.costMasked, true);
    assert.equal(version.baseAmount, null);
    assert.equal(version.vendorCode, "VENDOR-1");
  });
});

describe("parseRateSelection", () => {
  test("maps a raw app.rate_selections_directory row to the camelCase contract shape", () => {
    const selection = parseRateSelection({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      costing_request_id: REQUEST_ID,
      rate_version_id: null,
      is_adhoc: true,
      currency: null,
      amount: null,
      snapshot: null,
      cost_masked: true,
      override_reason: "spot quote",
      selected_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(selection.isAdhoc, true);
    assert.equal(selection.costMasked, true);
    assert.equal(selection.overrideReason, "spot quote");
  });
});
