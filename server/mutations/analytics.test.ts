import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { registerAnalyticsView, refreshAnalyticsView, AnalyticsMutationError, type AnalyticsMutationRpcClient } from "./analytics.ts";

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
  registered_by_auth_user_id: ACTOR_ID,
  registered_by: "tester",
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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: AnalyticsMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AnalyticsMutationRpcClient;
  return { client, calls };
}

describe("registerAnalyticsView", () => {
  test("calls register_analytics_view with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_VIEW_ROW, error: null });
    const view = await registerAnalyticsView(client, {
      viewCode: "report_usage_daily",
      viewName: "mv_report_usage_daily",
      name: "Report Usage (Daily)",
      sourceDomain: "reporting",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "register_analytics_view");
    assert.equal(calls[0]?.args.p_view_name, "mv_report_usage_daily");
    assert.equal(view.viewCode, "report_usage_daily");
  });

  test("classifies insufficient_authority (not Supreme Admin)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register an analytics view" } });
    await assert.rejects(
      () =>
        registerAnalyticsView(client, {
          viewCode: "x",
          viewName: "mv_x",
          name: "x",
          sourceDomain: "reporting",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tester",
        }),
      (err: unknown) => {
        assert.ok(err instanceof AnalyticsMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("refreshAnalyticsView", () => {
  test("calls refresh_analytics_view and returns the completed run", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_RUN_ROW, error: null });
    const run = await refreshAnalyticsView(client, { viewCode: "report_usage_daily", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "refresh_analytics_view");
    assert.equal(calls[0]?.args.p_view_code, "report_usage_daily");
    assert.equal(run.status, "completed");
    assert.equal(run.reconciled, true);
  });

  test("classifies analytics_view_unknown", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "analytics_view_unknown: not_a_view is not a registered analytics view" } });
    await assert.rejects(
      () => refreshAnalyticsView(client, { viewCode: "not_a_view", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AnalyticsMutationError);
        assert.equal(err.code, "analytics_view_unknown");
        return true;
      },
    );
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, something unrelated broke" } });
    await assert.rejects(
      () => refreshAnalyticsView(client, { viewCode: "report_usage_daily", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AnalyticsMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
