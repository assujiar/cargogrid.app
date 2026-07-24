import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  CreateSalesPlanInputSchema,
  CreateSalesTargetInputSchema,
  CaptureForecastSnapshotInputSchema,
  parseSalesPlan,
  parseSalesTarget,
  parseForecastSnapshot,
  parseWinLossReason,
  parsePipelineOutcome,
  parsePipelineStageSummaryEntry,
} from "./pipeline.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const PLAN_ID = "323e4567-e89b-12d3-a456-426614174000";
const TARGET_ID = "423e4567-e89b-12d3-a456-426614174000";
const CATEGORY_ID = "523e4567-e89b-12d3-a456-426614174000";
const ORG_UNIT_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const REASON_ID = "823e4567-e89b-12d3-a456-426614174000";
const PROSPECT_ID = "923e4567-e89b-12d3-a456-426614174000";
const OUTCOME_ID = "a23e4567-e89b-12d3-a456-426614174000";

describe("CreateSalesPlanInputSchema", () => {
  test("applies defaults for omitted optional fields", () => {
    const parsed = CreateSalesPlanInputSchema.parse({
      tenantId: TENANT_ID,
      name: "Q3 Plan",
      periodStart: "2026-07-01",
      periodEnd: "2026-09-30",
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.orgUnitId, null);
    assert.equal(parsed.ownerUserId, null);
  });
});

describe("CreateSalesTargetInputSchema", () => {
  test("rejects an unknown metric type", () => {
    assert.throws(() =>
      CreateSalesTargetInputSchema.parse({
        salesPlanId: PLAN_ID,
        metricType: "revenue_booked",
        targetValue: 10,
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });

  test("rejects a negative target value", () => {
    assert.throws(() =>
      CreateSalesTargetInputSchema.parse({
        salesPlanId: PLAN_ID,
        metricType: "leads_captured",
        targetValue: -1,
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });
});

describe("CaptureForecastSnapshotInputSchema", () => {
  test("defaults overrideValue/overrideReason to null", () => {
    const parsed = CaptureForecastSnapshotInputSchema.parse({
      salesTargetId: TARGET_ID,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.overrideValue, null);
    assert.equal(parsed.overrideReason, null);
  });
});

describe("parseSalesPlan", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const plan = parseSalesPlan({
      id: PLAN_ID,
      tenant_id: TENANT_ID,
      org_unit_id: ORG_UNIT_ID,
      name: "Q3 Plan",
      period_start: "2026-07-01",
      period_end: "2026-09-30",
      status: "draft",
      supersedes_plan_id: null,
      owner_user_id: null,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(plan.name, "Q3 Plan");
    assert.equal(plan.status, "draft");
  });
});

describe("parseSalesTarget", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const target = parseSalesTarget({
      id: TARGET_ID,
      tenant_id: TENANT_ID,
      sales_plan_id: PLAN_ID,
      pipeline_category_id: CATEGORY_ID,
      metric_type: "leads_captured",
      org_unit_id: ORG_UNIT_ID,
      owner_user_id: null,
      target_value: 10,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(target.metricType, "leads_captured");
    assert.equal(target.targetValue, 10);
  });
});

describe("parseForecastSnapshot", () => {
  test("maps an override snapshot correctly", () => {
    const snapshot = parseForecastSnapshot({
      id: "b23e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      sales_target_id: TARGET_ID,
      computed_value: 2,
      override_value: 5,
      override_reason: "Manual adjustment",
      snapshot_at: "2026-07-23T00:00:00.000Z",
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(snapshot.computedValue, 2);
    assert.equal(snapshot.overrideValue, 5);
  });
});

describe("parseWinLossReason", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const reason = parseWinLossReason({
      id: REASON_ID,
      tenant_id: TENANT_ID,
      code: "NO_BUDGET",
      label: "No budget",
      outcome: "lost",
      is_active: true,
      record_version: 1,
      created_by: "tester",
      created_at: "2026-07-23T00:00:00.000Z",
      updated_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(reason.code, "NO_BUDGET");
    assert.equal(reason.outcome, "lost");
  });
});

describe("parsePipelineOutcome", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const outcome = parsePipelineOutcome({
      id: OUTCOME_ID,
      tenant_id: TENANT_ID,
      related_type: "prospect",
      related_id: PROSPECT_ID,
      outcome: "lost",
      win_loss_reason_id: REASON_ID,
      notes: "Client had no budget",
      is_current: true,
      superseded_by_id: null,
      recorded_by: "tester",
      recorded_at: "2026-07-23T00:00:00.000Z",
    });
    assert.equal(outcome.relatedType, "prospect");
    assert.equal(outcome.isCurrent, true);
  });
});

describe("parsePipelineStageSummaryEntry", () => {
  test("coerces a string bigint record_count to a number", () => {
    const entry = parsePipelineStageSummaryEntry({ stage: "prospect_active", record_count: "3" });
    assert.equal(entry.recordCount, 3);
    assert.equal(typeof entry.recordCount, "number");
  });
});
