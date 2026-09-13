import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listAnalyticsViews, getLatestAnalyticsRefreshRun, listAnalyticsRefreshRuns, getReportUsageDaily, AnalyticsQueryError, type AnalyticsQueryClient } from "./analytics.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

const VALID_VIEW_ROW = {
  id: "423e4567-e89b-12d3-a456-426614174000",
  view_code: "report_usage_daily",
  view_name: "mv_report_usage_daily",
  name: "Report Usage (Daily)",
  description: "x",
  source_domain: "reporting",
  refresh_frequency_minutes: 60,
  status: "active",
  registered_by_auth_user_id: null,
  registered_by: "system",
  created_at: "2026-08-21T00:00:00.000Z",
};

const VALID_RUN_ROW = {
  id: "523e4567-e89b-12d3-a456-426614174000",
  view_code: "report_usage_daily",
  status: "completed",
  row_count_before: null,
  row_count_after: 3,
  reconciled: true,
  error_reason: null,
  triggered_by_auth_user_id: null,
  triggered_by_label: null,
  started_at: "2026-08-21T00:00:00.000Z",
  completed_at: "2026-08-21T00:00:01.000Z",
};

function fakeRpcClient(rpcResponses: Record<string, { data: unknown; error: { message: string } | null }>): {
  client: AnalyticsQueryClient;
  rpcCalls: { fn: string; args: Record<string, unknown> }[];
} {
  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown> = {}) {
      rpcCalls.push({ fn, args });
      return rpcResponses[fn] ?? { data: [], error: null };
    },
  } as unknown as AnalyticsQueryClient;
  return { client, rpcCalls };
}

describe("listAnalyticsViews", () => {
  test("calls list_analytics_view_registry and maps view rows", async () => {
    const { client, rpcCalls } = fakeRpcClient({ list_analytics_view_registry: { data: [VALID_VIEW_ROW], error: null } });
    const views = await listAnalyticsViews(client);
    assert.equal(rpcCalls[0]?.fn, "list_analytics_view_registry");
    assert.equal(views.length, 1);
    assert.equal(views[0]?.viewCode, "report_usage_daily");
  });

  test("wraps a query error", async () => {
    const { client } = fakeRpcClient({ list_analytics_view_registry: { data: null, error: { message: "boom" } } });
    await assert.rejects(
      () => listAnalyticsViews(client),
      (err: unknown) => err instanceof AnalyticsQueryError,
    );
  });
});

describe("getLatestAnalyticsRefreshRun", () => {
  test("returns null when never refreshed", async () => {
    const { client, rpcCalls } = fakeRpcClient({ get_latest_analytics_refresh_run: { data: [], error: null } });
    const run = await getLatestAnalyticsRefreshRun(client, "report_usage_daily");
    assert.equal(run, null);
    assert.equal(rpcCalls[0]?.fn, "get_latest_analytics_refresh_run");
    assert.deepEqual(rpcCalls[0]?.args, { p_view_code: "report_usage_daily" });
  });

  test("parses the latest run", async () => {
    const { client } = fakeRpcClient({ get_latest_analytics_refresh_run: { data: [VALID_RUN_ROW], error: null } });
    const run = await getLatestAnalyticsRefreshRun(client, "report_usage_daily");
    assert.equal(run?.status, "completed");
    assert.equal(run?.triggeredByLabel, null);
  });
});

describe("listAnalyticsRefreshRuns", () => {
  test("calls list_analytics_refresh_runs and maps run rows, newest first", async () => {
    const { client, rpcCalls } = fakeRpcClient({ list_analytics_refresh_runs: { data: [VALID_RUN_ROW], error: null } });
    const runs = await listAnalyticsRefreshRuns(client, "report_usage_daily");
    assert.deepEqual(rpcCalls[0]?.args, { p_view_code: "report_usage_daily", p_limit: 25 });
    assert.equal(runs.length, 1);
    assert.equal(runs[0]?.reconciled, true);
  });
});

describe("getReportUsageDaily", () => {
  test("calls get_report_usage_daily with the exact snake_case params", async () => {
    const usageRow = { report_type_code: "finance_billing_summary", usage_date: "2026-08-21T00:00:00.000Z", preview_count: 2, export_count: 1, failed_count: 0, last_run_at: "2026-08-21T00:00:00.000Z" };
    const { client, rpcCalls } = fakeRpcClient({ get_report_usage_daily: { data: [usageRow], error: null } });
    const rows = await getReportUsageDaily(client, TENANT_ID, ACTOR_ID, { reportTypeCode: "finance_billing_summary" });

    assert.equal(rpcCalls[0]?.fn, "get_report_usage_daily");
    assert.equal(rpcCalls[0]?.args.p_report_type_code, "finance_billing_summary");
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.previewCount, 2);
  });

  test("wraps an authority error", async () => {
    const { client } = fakeRpcClient({ get_report_usage_daily: { data: null, error: { message: "insufficient_authority: no membership" } } });
    await assert.rejects(
      () => getReportUsageDaily(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => err instanceof AnalyticsQueryError,
    );
  });
});
