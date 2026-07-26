import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  DashboardScopeFilterSchema,
  DashboardPeriodFilterSchema,
  parseLeadAgingEntry,
  parseActivityQueueEntry,
  parsePipelineSummaryEntry,
  parseQuoteSlaEntry,
  parseMarginSummaryEntry,
  parseWinLossSummaryEntry,
  parseForecastSummaryEntry,
} from "./dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";

describe("DashboardScopeFilterSchema", () => {
  test("defaults orgUnitId/ownerUserId to null", () => {
    const parsed = DashboardScopeFilterSchema.parse({ tenantId: TENANT_ID });
    assert.equal(parsed.orgUnitId, null);
    assert.equal(parsed.ownerUserId, null);
  });

  test("rejects a non-uuid tenantId", () => {
    assert.throws(() => DashboardScopeFilterSchema.parse({ tenantId: "not-a-uuid" }));
  });
});

describe("DashboardPeriodFilterSchema", () => {
  test("accepts ISO date-only periodStart/periodEnd", () => {
    const parsed = DashboardPeriodFilterSchema.parse({ tenantId: TENANT_ID, periodStart: "2026-07-01", periodEnd: "2026-07-26" });
    assert.equal(parsed.periodStart, "2026-07-01");
    assert.equal(parsed.periodEnd, "2026-07-26");
  });

  test("rejects a full timestamp for periodStart", () => {
    assert.throws(() => DashboardPeriodFilterSchema.parse({ tenantId: TENANT_ID, periodStart: "2026-07-01T00:00:00.000Z" }));
  });

  test("defaults periodStart/periodEnd to null (unbounded)", () => {
    const parsed = DashboardPeriodFilterSchema.parse({ tenantId: TENANT_ID });
    assert.equal(parsed.periodStart, null);
    assert.equal(parsed.periodEnd, null);
  });
});

describe("parseLeadAgingEntry", () => {
  test("coerces the bigint-shaped lead_count into a number", () => {
    const entry = parseLeadAgingEntry({ bucket: "0_2_days", lead_count: "4" });
    assert.equal(entry.leadCount, 4);
  });

  test("rejects an unknown bucket", () => {
    assert.throws(() => parseLeadAgingEntry({ bucket: "not_a_bucket", lead_count: 1 }));
  });
});

describe("parseActivityQueueEntry", () => {
  test("maps activity_count", () => {
    const entry = parseActivityQueueEntry({ bucket: "overdue", activity_count: 2 });
    assert.equal(entry.bucket, "overdue");
    assert.equal(entry.activityCount, 2);
  });
});

describe("parsePipelineSummaryEntry", () => {
  test("maps a masked row (null currency/value, valueMasked=true) without coercing null to zero", () => {
    const entry = parsePipelineSummaryEntry({
      stage: "qualifying",
      currency: null,
      opportunity_count: 3,
      value_amount_total: null,
      value_masked: true,
    });
    assert.equal(entry.valueAmountTotal, null);
    assert.equal(entry.valueMasked, true);
    assert.equal(entry.opportunityCount, 3);
  });

  test("maps an unmasked row with a real total", () => {
    const entry = parsePipelineSummaryEntry({
      stage: "ready_for_costing",
      currency: "IDR",
      opportunity_count: 1,
      value_amount_total: 200000000,
      value_masked: false,
    });
    assert.equal(entry.valueAmountTotal, 200000000);
    assert.equal(entry.valueMasked, false);
  });
});

describe("parseQuoteSlaEntry", () => {
  test("maps quote_count", () => {
    const entry = parseQuoteSlaEntry({ bucket: "expiring_soon", quote_count: 1 });
    assert.equal(entry.bucket, "expiring_soon");
    assert.equal(entry.quoteCount, 1);
  });
});

describe("parseMarginSummaryEntry", () => {
  test("maps a masked row", () => {
    const entry = parseMarginSummaryEntry({
      currency: "IDR",
      calculation_count: 2,
      avg_margin_pct: null,
      total_margin_amount: null,
      margin_masked: true,
    });
    assert.equal(entry.avgMarginPct, null);
    assert.equal(entry.marginMasked, true);
  });
});

describe("parseWinLossSummaryEntry", () => {
  test("maps an unmasked won row", () => {
    const entry = parseWinLossSummaryEntry({
      outcome: "won",
      currency: "IDR",
      opportunity_count: 1,
      value_amount_total: 150000000,
      value_masked: false,
    });
    assert.equal(entry.outcome, "won");
    assert.equal(entry.valueAmountTotal, 150000000);
  });
});

describe("parseForecastSummaryEntry", () => {
  test("maps a masked forecast row", () => {
    const entry = parseForecastSummaryEntry({
      currency: "IDR",
      open_opportunity_count: 2,
      weighted_value_total: null,
      value_masked: true,
    });
    assert.equal(entry.weightedValueTotal, null);
    assert.equal(entry.valueMasked, true);
  });
});
