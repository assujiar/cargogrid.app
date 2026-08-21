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
  row_count_before: 2,
  row_count_after: 3,
  reconciled: true,
  error_reason: null,
  triggered_by_auth_user_id: ACTOR_ID,
  triggered_by_label: "tester",
  started_at: "2026-08-21T00:00:00.000Z",
  completed_at: "2026-08-21T00:00:01.000Z",
};

function fakeClient(tableResponse: { data: unknown; error: { message: string } | null }, rpcResponse?: { data: unknown; error: { message: string } | null }): {
  client: AnalyticsQueryClient;
  rpcCalls: { fn: string; args: Record<string, unknown> }[];
} {
  const rpcCalls: { fn: string; args: Record<string, unknown> }[] = [];
  function chainNode(): unknown {
    return {
      select: () => chainNode(),
      eq: () => chainNode(),
      order: () => chainNode(),
      limit: () => chainNode(),
      maybeSingle: () => {
        const row = Array.isArray(tableResponse.data) ? (tableResponse.data[0] ?? null) : tableResponse.data;
        return Promise.resolve({ data: row, error: tableResponse.error });
      },
      then: (resolve: (value: unknown) => unknown, reject?: (reason: unknown) => unknown) => Promise.resolve(tableResponse).then(resolve, reject),
    };
  }
  const client = {
    from: () => chainNode(),
    async rpc(fn: string, args: Record<string, unknown>) {
      rpcCalls.push({ fn, args });
      return rpcResponse ?? { data: [], error: null };
    },
  } as unknown as AnalyticsQueryClient;
  return { client, rpcCalls };
}

describe("listAnalyticsViews", () => {
  test("maps view rows", async () => {
    const { client } = fakeClient({ data: [VALID_VIEW_ROW], error: null });
    const views = await listAnalyticsViews(client);
    assert.equal(views.length, 1);
    assert.equal(views[0]?.viewCode, "report_usage_daily");
  });

  test("wraps a query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listAnalyticsViews(client),
      (err: unknown) => err instanceof AnalyticsQueryError,
    );
  });
});

describe("getLatestAnalyticsRefreshRun", () => {
  test("returns null when never refreshed", async () => {
    const { client } = fakeClient({ data: null, error: null });
    const run = await getLatestAnalyticsRefreshRun(client, "report_usage_daily");
    assert.equal(run, null);
  });

  test("parses the latest run", async () => {
    const { client } = fakeClient({ data: VALID_RUN_ROW, error: null });
    const run = await getLatestAnalyticsRefreshRun(client, "report_usage_daily");
    assert.equal(run?.status, "completed");
  });
});

describe("listAnalyticsRefreshRuns", () => {
  test("maps run rows, newest first", async () => {
    const { client } = fakeClient({ data: [VALID_RUN_ROW], error: null });
    const runs = await listAnalyticsRefreshRuns(client, "report_usage_daily");
    assert.equal(runs.length, 1);
    assert.equal(runs[0]?.reconciled, true);
  });
});

describe("getReportUsageDaily", () => {
  test("calls get_report_usage_daily with the exact snake_case params", async () => {
    const usageRow = { report_type_code: "finance_billing_summary", usage_date: "2026-08-21T00:00:00.000Z", preview_count: 2, export_count: 1, failed_count: 0, last_run_at: "2026-08-21T00:00:00.000Z" };
    const { client, rpcCalls } = fakeClient({ data: null, error: null }, { data: [usageRow], error: null });
    const rows = await getReportUsageDaily(client, TENANT_ID, ACTOR_ID, { reportTypeCode: "finance_billing_summary" });

    assert.equal(rpcCalls[0]?.fn, "get_report_usage_daily");
    assert.equal(rpcCalls[0]?.args.p_report_type_code, "finance_billing_summary");
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.previewCount, 2);
  });

  test("wraps an authority error", async () => {
    const { client } = fakeClient({ data: null, error: null }, { data: null, error: { message: "insufficient_authority: no membership" } });
    await assert.rejects(
      () => getReportUsageDaily(client, TENANT_ID, ACTOR_ID),
      (err: unknown) => err instanceof AnalyticsQueryError,
    );
  });
});
