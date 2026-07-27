import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseJobOrder,
  parseJobOrderOverride,
  parseJobOrderConversionReadiness,
  PrepareJobOrderInputSchema,
  ConfirmJobOrderInputSchema,
  OverrideJobOrderFieldInputSchema,
} from "./job-order.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "423e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const BASE_ROW = {
  id: JOB_ORDER_ID,
  tenant_id: TENANT_ID,
  job_number: "JOB-2026-000001",
  source_handoff_id: HANDOFF_ID,
  quotation_id: QUOTATION_ID,
  account_id: ACCOUNT_ID,
  customer_snapshot: { accountId: ACCOUNT_ID, customerSnapshot: { legal_name: "Ops Test Co" } },
  cargo_service_snapshot: { service_type: "ocean_freight" },
  contract_snapshot: null,
  acceptance_snapshot: { decidedByName: "Jane Ops", decidedAt: "2026-07-27T00:00:00.000Z", decision: "accepted" },
  status: "draft",
  owner_user_id: ACTOR_ID,
  org_unit_id: null,
  record_version: 1,
  created_by: "tester",
  created_at: "2026-07-27T00:00:00.000Z",
  updated_at: "2026-07-27T00:00:00.000Z",
};

describe("parseJobOrder", () => {
  test("maps an unmasked row", () => {
    const jobOrder = parseJobOrder({
      ...BASE_ROW,
      revenue_snapshot: { currency: "IDR", totalAmount: 15000000 },
      revenue_masked: false,
      credit_snapshot: { outcome: "pass", checkedAt: "2026-07-27T00:00:00.000Z" },
      credit_masked: false,
    });
    assert.equal(jobOrder.revenueMasked, false);
    assert.equal(jobOrder.creditMasked, false);
    assert.equal((jobOrder.revenueSnapshot as { totalAmount: number }).totalAmount, 15000000);
  });

  test("maps a masked row without coercing nulled snapshots into empty objects", () => {
    const jobOrder = parseJobOrder({
      ...BASE_ROW,
      revenue_snapshot: null,
      revenue_masked: true,
      credit_snapshot: null,
      credit_masked: true,
    });
    assert.equal(jobOrder.revenueSnapshot, null);
    assert.equal(jobOrder.revenueMasked, true);
    assert.equal(jobOrder.creditSnapshot, null);
    assert.equal(jobOrder.creditMasked, true);
  });
});

describe("parseJobOrderOverride", () => {
  test("maps an append-only override row", () => {
    const override = parseJobOrderOverride({
      id: "823e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      job_order_id: JOB_ORDER_ID,
      snapshot_column: "customer_snapshot",
      field_path: "contactPhone",
      previous_value: "0811",
      new_value: "0899",
      reason: "customer provided a new phone number",
      overridden_by: "rep",
      overridden_at: "2026-07-27T00:00:00.000Z",
    });
    assert.equal(override.snapshotColumn, "customer_snapshot");
    assert.equal(override.reason, "customer provided a new phone number");
  });
});

describe("parseJobOrderConversionReadiness", () => {
  test("defaults blockingReasons to an empty array, not null", () => {
    const readiness = parseJobOrderConversionReadiness({ ready: true, blocking_reasons: null, existing_job_order_id: null });
    assert.deepEqual(readiness.blockingReasons, []);
    assert.equal(readiness.existingJobOrderId, null);
  });
});

describe("PrepareJobOrderInputSchema", () => {
  test("requires a non-empty actorLabel", () => {
    assert.throws(() => PrepareJobOrderInputSchema.parse({ sourceHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID, actorLabel: "" }));
  });
});

describe("ConfirmJobOrderInputSchema", () => {
  test("requires a positive expectedVersion", () => {
    assert.throws(() =>
      ConfirmJobOrderInputSchema.parse({ jobOrderId: JOB_ORDER_ID, expectedVersion: 0, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});

describe("OverrideJobOrderFieldInputSchema", () => {
  test("requires a non-empty reason", () => {
    assert.throws(() =>
      OverrideJobOrderFieldInputSchema.parse({
        jobOrderId: JOB_ORDER_ID,
        expectedVersion: 1,
        snapshotColumn: "customer_snapshot",
        fieldPath: "contactPhone",
        newValue: "0899",
        reason: "",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });

  test("rejects a non-overridable snapshot column", () => {
    assert.throws(() =>
      OverrideJobOrderFieldInputSchema.parse({
        jobOrderId: JOB_ORDER_ID,
        expectedVersion: 1,
        snapshotColumn: "revenue_snapshot",
        fieldPath: "totalAmount",
        newValue: 99,
        reason: "attempted financial edit",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});
