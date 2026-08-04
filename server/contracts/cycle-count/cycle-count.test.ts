import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseCycleCountPlan,
  parseCycleCountScopeItem,
  parseCycleCountObservation,
  CycleCountPlanSchema,
  CreateCycleCountPlanInputSchema,
  RecordCycleCountObservationInputSchema,
} from "./cycle-count.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const WAREHOUSE_ID = "323e4567-e89b-12d3-a456-426614174000";
const PLAN_ID = "423e4567-e89b-12d3-a456-426614174000";
const SCOPE_ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "623e4567-e89b-12d3-a456-426614174000";
const ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";
const LOCATION_ID = "823e4567-e89b-12d3-a456-426614174000";
const BALANCE_ID = "923e4567-e89b-12d3-a456-426614174000";
const OBSERVATION_ID = "a23e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "b23e4567-e89b-12d3-a456-426614174000";

describe("parseCycleCountPlan", () => {
  test("maps a draft plan row", () => {
    const plan = parseCycleCountPlan({
      id: PLAN_ID,
      tenant_id: TENANT_ID,
      warehouse_id: WAREHOUSE_ID,
      plan_number: "CC-2026-000001",
      method: "full",
      variance_threshold_pct: "0",
      recount_threshold_pct: "5",
      requires_separate_approver: true,
      status: "draft",
      scope_filter_zone_id: null,
      scope_filter_location_id: null,
      scope_filter_item_master_id: null,
      scope_filter_owner_account_id: null,
      frozen_at: null,
      closed_at: null,
      idempotency_key: "idem-plan-1",
      record_version: 1,
      created_by: "rep",
      created_at: "2026-08-03T00:00:00.000Z",
      updated_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(plan.planNumber, "CC-2026-000001");
    assert.equal(plan.status, "draft");
    assert.equal(plan.frozenAt, null);
  });

  test("rejects an invalid status via the schema", () => {
    assert.throws(() =>
      CycleCountPlanSchema.parse({
        id: PLAN_ID,
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        planNumber: "CC-2026-000001",
        method: "full",
        varianceThresholdPct: 0,
        recountThresholdPct: 5,
        requiresSeparateApprover: true,
        status: "not_a_real_status",
        scopeFilterZoneId: null,
        scopeFilterLocationId: null,
        scopeFilterItemMasterId: null,
        scopeFilterOwnerAccountId: null,
        frozenAt: null,
        closedAt: null,
        idempotencyKey: "idem-plan-1",
        recordVersion: 1,
        createdBy: "rep",
        createdAt: "2026-08-03T00:00:00.000Z",
        updatedAt: "2026-08-03T00:00:00.000Z",
      }),
    );
  });
});

describe("parseCycleCountScopeItem", () => {
  const baseRow = {
    id: SCOPE_ITEM_ID,
    tenant_id: TENANT_ID,
    plan_id: PLAN_ID,
    warehouse_id: WAREHOUSE_ID,
    owner_account_id: OWNER_ID,
    item_master_id: ITEM_ID,
    location_id: LOCATION_ID,
    lot_number: null,
    serial_number: null,
    uom_code: "PCS",
    snapshot_balance_id: BALANCE_ID,
    snapshot_taken_at: "2026-08-03T00:00:00.000Z",
    status: "pending",
    assigned_to_auth_user_id: null,
    assigned_to_label: null,
    assigned_at: null,
    count_attempt_number: 0,
    last_observed_quantity: null,
    variance_quantity: null,
    variance_pct: null,
    reviewed_by_auth_user_id: null,
    reviewed_by_label: null,
    reviewed_at: null,
    review_reason: null,
    adjustment_movement_id: null,
    record_version: 1,
    created_at: "2026-08-03T00:00:00.000Z",
    updated_at: "2026-08-03T00:00:00.000Z",
  };

  test("maps a full row with visible expected/variance quantities (supervisor view)", () => {
    const item = parseCycleCountScopeItem({ ...baseRow, snapshot_expected_quantity: "100", snapshot_record_version: 3 });
    assert.equal(item.snapshotExpectedQuantity, 100);
    assert.equal(item.snapshotRecordVersion, 3);
  });

  test("maps a blind-redacted row (plain counter view) -- expected/variance/snapshot version all null", () => {
    const item = parseCycleCountScopeItem({
      ...baseRow,
      snapshot_expected_quantity: null,
      snapshot_record_version: null,
      variance_quantity: null,
      variance_pct: null,
    });
    assert.equal(item.snapshotExpectedQuantity, null);
    assert.equal(item.snapshotRecordVersion, null);
    assert.equal(item.varianceQuantity, null);
    assert.equal(item.variancePct, null);
  });
});

describe("parseCycleCountObservation", () => {
  test("maps an observation row, including a zero observed quantity", () => {
    const observation = parseCycleCountObservation({
      id: OBSERVATION_ID,
      tenant_id: TENANT_ID,
      scope_item_id: SCOPE_ITEM_ID,
      attempt_number: 1,
      observed_quantity: "0",
      observed_uom_code: "PCS",
      scanned_location_id: LOCATION_ID,
      scanned_item_master_id: ITEM_ID,
      scanned_lot_number: null,
      scanned_serial_number: null,
      idempotency_key: "idem-obs-1",
      counted_by_auth_user_id: ACTOR_ID,
      counted_by_label: "counter",
      counted_at: "2026-08-03T00:00:00.000Z",
    });
    assert.equal(observation.observedQuantity, 0);
    assert.equal(observation.attemptNumber, 1);
  });
});

describe("CreateCycleCountPlanInputSchema", () => {
  test("accepts a minimal valid input", () => {
    const parsed = CreateCycleCountPlanInputSchema.parse({
      tenantId: TENANT_ID,
      warehouseId: WAREHOUSE_ID,
      varianceThresholdPct: 0,
      recountThresholdPct: 5,
      idempotencyKey: "idem-plan-1",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "rep",
    });
    assert.equal(parsed.varianceThresholdPct, 0);
  });

  test("rejects a negative variance threshold", () => {
    assert.throws(() =>
      CreateCycleCountPlanInputSchema.parse({
        tenantId: TENANT_ID,
        warehouseId: WAREHOUSE_ID,
        varianceThresholdPct: -1,
        recountThresholdPct: 5,
        idempotencyKey: "idem-plan-1",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "rep",
      }),
    );
  });
});

describe("RecordCycleCountObservationInputSchema", () => {
  test("accepts an explicit zero observed quantity", () => {
    const parsed = RecordCycleCountObservationInputSchema.parse({
      scopeItemId: SCOPE_ITEM_ID,
      observedQuantity: 0,
      observedUomCode: "PCS",
      scannedLocationId: LOCATION_ID,
      scannedItemMasterId: ITEM_ID,
      idempotencyKey: "idem-obs-1",
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "counter",
    });
    assert.equal(parsed.observedQuantity, 0);
  });

  test("rejects a negative observed quantity", () => {
    assert.throws(() =>
      RecordCycleCountObservationInputSchema.parse({
        scopeItemId: SCOPE_ITEM_ID,
        observedQuantity: -1,
        observedUomCode: "PCS",
        scannedLocationId: LOCATION_ID,
        scannedItemMasterId: ITEM_ID,
        idempotencyKey: "idem-obs-1",
        expectedVersion: 1,
        actorAuthUserId: ACTOR_ID,
        actorLabel: "counter",
      }),
    );
  });
});
