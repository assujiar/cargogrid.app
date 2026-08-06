import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createProcurementRateVersion,
  selectProcurementVendorRate,
  addVendorRateTier,
  removeVendorRateTier,
  calculateVendorRate,
  validateVendorRateImportRow,
  commitVendorRateImportJob,
  ProcurementRateMutationError,
  type ProcurementRateMutationRpcClient,
} from "./procurement-rate.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RATE_VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const MASTER_RECORD_ID = "423e4567-e89b-12d3-a456-426614174000";
const VENDOR_MASTER_ID = "923e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "623e4567-e89b-12d3-a456-426614174000";
const SELECTION_ID = "723e4567-e89b-12d3-a456-426614174000";
const TIER_ID = "823e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "a23e4567-e89b-12d3-a456-426614174000";
const STAGING_ROW_ID = "b23e4567-e89b-12d3-a456-426614174000";

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

const VALID_CALCULATION_ROW = {
  rate_version_id: RATE_VERSION_ID,
  matched_tier_id: TIER_ID,
  currency: "IDR",
  base_component: 15000000,
  tier_component: 500000,
  surcharge_component: 0,
  subtotal_amount: 500000,
  minimum_amount_applied: false,
  computed_amount: 500000,
  rounding_mode: "round_half_up",
  rounding_precision: 2,
  uom_basis: { weight_uom: "kg" },
  component_breakdown: { base_amount: 15000000 },
  computed_at: "2026-07-24T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, calls: { fn: string; args: Record<string, unknown> }[]): ProcurementRateMutationRpcClient {
  return {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ProcurementRateMutationRpcClient;
}

describe("createProcurementRateVersion", () => {
  test("passes the vendor_master_id/lead_time_days/capacity_terms trailing params through", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { ...VALID_RATE_VERSION_ROW, vendor_master_id: VENDOR_MASTER_ID, lead_time_days: 5, capacity_terms: "20ft x 4/week" }, error: null }, calls);

    const version = await createProcurementRateVersion(client, {
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
      vendorMasterId: VENDOR_MASTER_ID,
      leadTimeDays: 5,
      capacityTerms: "20ft x 4/week",
    });

    assert.equal(calls[0]?.fn, "create_rate_version");
    assert.equal(calls[0]?.args.p_vendor_master_id, VENDOR_MASTER_ID);
    assert.equal(calls[0]?.args.p_lead_time_days, 5);
    assert.equal(calls[0]?.args.p_capacity_terms, "20ft x 4/week");
    assert.equal(calls[0]?.args.p_source_import_staging_row_id, null);
    assert.equal(version.id, RATE_VERSION_ID);
  });

  test("defaults the trailing params to null when omitted", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_RATE_VERSION_ROW, error: null }, calls);

    await createProcurementRateVersion(client, {
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

    assert.equal(calls[0]?.args.p_vendor_master_id, null);
    assert.equal(calls[0]?.args.p_lead_time_days, null);
    assert.equal(calls[0]?.args.p_capacity_terms, null);
  });

  test("classifies vendor_not_active-shaped errors via the generic prefix classifier", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "invalid_vendor_identity: master record x is master_type_code vendor_rate, expected vendor" } }, []);
    await assert.rejects(
      () =>
        createProcurementRateVersion(client, {
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
          vendorMasterId: VENDOR_MASTER_ID,
        }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementRateMutationError);
        assert.equal(err.code, "invalid_vendor_identity");
        return true;
      },
    );
  });
});

describe("selectProcurementVendorRate", () => {
  test("passes weight/volume/quantity through when supplied", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_SELECTION_ROW, error: null }, calls);

    await selectProcurementVendorRate(client, {
      costingRequestId: REQUEST_ID,
      rateVersionId: RATE_VERSION_ID,
      isAdhoc: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
      weight: 50,
      volume: 2,
      quantity: 1,
    });

    assert.equal(calls[0]?.fn, "select_vendor_rate");
    assert.equal(calls[0]?.args.p_weight, 50);
    assert.equal(calls[0]?.args.p_volume, 2);
    assert.equal(calls[0]?.args.p_quantity, 1);
  });

  test("defaults weight/volume/quantity to null when omitted (byte-for-byte COM-149 backward compatibility)", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_SELECTION_ROW, error: null }, calls);

    await selectProcurementVendorRate(client, {
      costingRequestId: REQUEST_ID,
      rateVersionId: RATE_VERSION_ID,
      isAdhoc: false,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.args.p_weight, null);
    assert.equal(calls[0]?.args.p_volume, null);
    assert.equal(calls[0]?.args.p_quantity, null);
  });
});

describe("addVendorRateTier", () => {
  test("calls add_vendor_rate_tier with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: VALID_TIER_ROW, error: null }, calls);

    const tier = await addVendorRateTier(client, {
      rateVersionId: RATE_VERSION_ID,
      tierOrder: 1,
      weightMin: 0,
      weightMax: 100,
      volumeMin: null,
      volumeMax: null,
      amount: 500000,
      minimumCharge: null,
      idempotencyKey: "idem-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "add_vendor_rate_tier");
    assert.equal(calls[0]?.args.p_tier_order, 1);
    assert.equal(calls[0]?.args.p_weight_max, 100);
    assert.equal(calls[0]?.args.p_idempotency_key, "idem-1");
    assert.equal(tier.id, TIER_ID);
    assert.equal(tier.amount, 500000);
  });

  test("classifies tier_overlap/duplicate_tier_order-shaped errors", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "duplicate_tier_order: rate version x already has a tier at tier_order 1" } }, []);
    await assert.rejects(
      () =>
        addVendorRateTier(client, {
          rateVersionId: RATE_VERSION_ID,
          tierOrder: 1,
          amount: 1,
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementRateMutationError);
        assert.equal(err.code, "duplicate_tier_order");
        return true;
      },
    );
  });
});

describe("removeVendorRateTier", () => {
  test("calls remove_vendor_rate_tier with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: null, error: null }, calls);

    await removeVendorRateTier(client, { tierId: TIER_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "remove_vendor_rate_tier");
    assert.equal(calls[0]?.args.p_tier_id, TIER_ID);
    assert.equal(calls[0]?.args.p_expected_version, 1);
  });
});

describe("calculateVendorRate", () => {
  test("parses the single-row calculate_vendor_rate table response", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: [VALID_CALCULATION_ROW], error: null }, calls);

    const result = await calculateVendorRate(client, { rateVersionId: RATE_VERSION_ID, weight: 50, volume: null, quantity: null, actorAuthUserId: ACTOR_ID });

    assert.equal(calls[0]?.fn, "calculate_vendor_rate");
    assert.equal(calls[0]?.args.p_weight, 50);
    assert.equal(result.matchedTierId, TIER_ID);
    assert.equal(result.computedAmount, 500000);
    assert.equal(result.roundingMode, "round_half_up");
  });

  test("classifies an empty array response as invalid_response", async () => {
    const client = fakeRpcClient({ data: [], error: null }, []);
    await assert.rejects(
      () => calculateVendorRate(client, { rateVersionId: RATE_VERSION_ID, weight: null, volume: null, quantity: null, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementRateMutationError);
        assert.equal(err.code, "invalid_response");
        return true;
      },
    );
  });

  test("classifies insufficient_authority (PRC:View cost)", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity x lacks PRC:View cost (no_permission) for tenant y" } }, []);
    await assert.rejects(
      () => calculateVendorRate(client, { rateVersionId: RATE_VERSION_ID, weight: null, volume: null, quantity: null, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementRateMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("validateVendorRateImportRow", () => {
  test("calls validate_vendor_rate_import_row with the exact snake_case params", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { id: STAGING_ROW_ID, validation_status: "valid" }, error: null }, calls);

    const row = await validateVendorRateImportRow(client, { stagingRowId: STAGING_ROW_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "validate_vendor_rate_import_row");
    assert.equal(calls[0]?.args.p_staging_row_id, STAGING_ROW_ID);
    assert.equal(row.validation_status, "valid");
  });
});

describe("commitVendorRateImportJob", () => {
  test("calls commit_vendor_rate_import_job with the exact snake_case params, defaulting allowPartial to false", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = fakeRpcClient({ data: { job_id: JOB_ID, status: "completed" }, error: null }, calls);

    const job = await commitVendorRateImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "commit_vendor_rate_import_job");
    assert.equal(calls[0]?.args.p_job_id, JOB_ID);
    assert.equal(calls[0]?.args.p_allow_partial, false);
    assert.equal(job.status, "completed");
  });

  test("classifies import_export_job_has_invalid_rows", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "import_export_job_has_invalid_rows: job x has 2 invalid row(s); pass p_allow_partial to accept a partial commit" } }, []);
    await assert.rejects(
      () => commitVendorRateImportJob(client, { jobId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof ProcurementRateMutationError);
        assert.equal(err.code, "import_export_job_has_invalid_rows");
        return true;
      },
    );
  });
});
