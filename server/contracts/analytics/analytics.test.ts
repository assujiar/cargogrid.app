import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseAnalyticsViewRegistry, parseAnalyticsRefreshRun, parseReportUsageDailyRow, RegisterAnalyticsViewInputSchema, RefreshAnalyticsViewInputSchema } from "./analytics.ts";

const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const VIEW_ID = "423e4567-e89b-12d3-a456-426614174000";
const RUN_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseAnalyticsViewRegistry", () => {
  test("maps snake_case fields", () => {
    const view = parseAnalyticsViewRegistry({
      id: VIEW_ID,
      view_code: "report_usage_daily",
      view_name: "mv_report_usage_daily",
      name: "Report Usage (Daily)",
      description: "x",
      source_domain: "reporting",
      refresh_frequency_minutes: 60,
      status: "active",
      registered_by_auth_user_id: ACTOR_ID,
      registered_by: "system",
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(view.viewName, "mv_report_usage_daily");
    assert.equal(view.status, "active");
  });
});

describe("parseAnalyticsRefreshRun", () => {
  test("maps a completed, reconciled run", () => {
    const run = parseAnalyticsRefreshRun({
      id: RUN_ID,
      view_code: "report_usage_daily",
      status: "completed",
      row_count_before: 2,
      row_count_after: 3,
      reconciled: true,
      error_reason: null,
      triggered_by_auth_user_id: ACTOR_ID,
      triggered_by_label: "tester",
      started_at: "2026-08-21T00:00:00.000Z",
      completed_at: "2026-08-21T00:00:01.000Z",
    });
    assert.equal(run.status, "completed");
    assert.equal(run.reconciled, true);
    assert.equal(run.rowCountAfter, 3);
  });

  test("maps a failed run with a real error reason", () => {
    const run = parseAnalyticsRefreshRun({
      id: RUN_ID,
      view_code: "report_usage_daily",
      status: "failed",
      row_count_before: null,
      row_count_after: null,
      reconciled: null,
      error_reason: "relation \"app.mv_x\" does not exist",
      triggered_by_auth_user_id: ACTOR_ID,
      triggered_by_label: "tester",
      started_at: "2026-08-21T00:00:00.000Z",
      completed_at: "2026-08-21T00:00:01.000Z",
    });
    assert.equal(run.status, "failed");
    assert.ok(run.errorReason);
  });
});

describe("parseReportUsageDailyRow", () => {
  test("maps snake_case fields", () => {
    const row = parseReportUsageDailyRow({
      report_type_code: "finance_billing_summary",
      usage_date: "2026-08-21T00:00:00.000Z",
      preview_count: 2,
      export_count: 1,
      failed_count: 0,
      last_run_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(row.reportTypeCode, "finance_billing_summary");
    assert.equal(row.previewCount, 2);
  });
});

describe("RegisterAnalyticsViewInputSchema", () => {
  test("defaults refreshFrequencyMinutes to 60 and description to null", () => {
    const parsed = RegisterAnalyticsViewInputSchema.parse({
      viewCode: "report_usage_daily",
      viewName: "mv_report_usage_daily",
      name: "Report Usage",
      sourceDomain: "reporting",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.refreshFrequencyMinutes, 60);
    assert.equal(parsed.description, null);
  });
});

describe("RefreshAnalyticsViewInputSchema", () => {
  test("requires a non-empty viewCode", () => {
    assert.throws(() => RefreshAnalyticsViewInputSchema.parse({ viewCode: "", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }));
  });
});
