import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getDashboardLeadAging,
  getDashboardActivityQueue,
  getDashboardPipelineSummary,
  getDashboardQuoteSla,
  getDashboardMarginSummary,
  getDashboardWinLossSummary,
  getDashboardForecastSummary,
  DashboardQueryError,
  DashboardQueryTimeoutError,
  type DashboardQueryRpcClient,
} from "./dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ORG_UNIT_ID = "323e4567-e89b-12d3-a456-426614174000";
const OWNER_ID = "423e4567-e89b-12d3-a456-426614174000";

function recordingClient(response: { data: unknown; error: { message: string } | null }): {
  client: DashboardQueryRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as DashboardQueryRpcClient;
  return { client, calls };
}

describe("getDashboardLeadAging", () => {
  test("calls get_dashboard_lead_aging with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({ data: [{ bucket: "0_2_days", lead_count: 1 }], error: null });
    const entries = await getDashboardLeadAging(client, { tenantId: TENANT_ID, orgUnitId: ORG_UNIT_ID, ownerUserId: OWNER_ID });

    assert.equal(calls[0]?.fn, "get_dashboard_lead_aging");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_org_unit_id: ORG_UNIT_ID, p_owner_user_id: OWNER_ID });
    assert.equal(entries.length, 1);
    assert.equal(entries[0]?.leadCount, 1);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => getDashboardLeadAging(client, { tenantId: TENANT_ID }),
      (err: unknown) => err instanceof DashboardQueryError,
    );
  });

  test("rejects with a non-array result", async () => {
    const { client } = recordingClient({ data: { not: "an array" }, error: null });
    await assert.rejects(
      () => getDashboardLeadAging(client, { tenantId: TENANT_ID }),
      (err: unknown) => err instanceof DashboardQueryError,
    );
  });

  test("rejects with DashboardQueryTimeoutError once the query budget elapses", async () => {
    const client = {
      rpc() {
        return new Promise(() => {
          // Deliberately never resolves -- proves the budget timer, not the RPC, wins.
        });
      },
    } as unknown as DashboardQueryRpcClient;
    await assert.rejects(
      () => getDashboardLeadAging(client, { tenantId: TENANT_ID }, { budgetMs: 10 }),
      (err: unknown) => {
        assert.ok(err instanceof DashboardQueryTimeoutError);
        assert.match((err as Error).message, /get_dashboard_lead_aging/);
        return true;
      },
    );
  });
});

describe("getDashboardActivityQueue", () => {
  test("calls get_dashboard_activity_queue and maps activity_count", async () => {
    const { client, calls } = recordingClient({ data: [{ bucket: "overdue", activity_count: 2 }], error: null });
    const entries = await getDashboardActivityQueue(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_dashboard_activity_queue");
    assert.equal(entries[0]?.activityCount, 2);
  });
});

describe("getDashboardPipelineSummary", () => {
  test("maps a masked entry without turning a null total into zero", async () => {
    const { client } = recordingClient({
      data: [{ stage: "qualifying", currency: null, opportunity_count: 1, value_amount_total: null, value_masked: true }],
      error: null,
    });
    const entries = await getDashboardPipelineSummary(client, { tenantId: TENANT_ID });
    assert.equal(entries[0]?.valueAmountTotal, null);
    assert.equal(entries[0]?.valueMasked, true);
  });
});

describe("getDashboardQuoteSla", () => {
  test("calls get_dashboard_quote_sla and maps quote_count", async () => {
    const { client, calls } = recordingClient({ data: [{ bucket: "pending_approval", quote_count: 1 }], error: null });
    const entries = await getDashboardQuoteSla(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_dashboard_quote_sla");
    assert.equal(entries[0]?.quoteCount, 1);
  });
});

describe("getDashboardMarginSummary", () => {
  test("passes the period window as snake_case params", async () => {
    const { client, calls } = recordingClient({
      data: [{ currency: "IDR", calculation_count: 2, avg_margin_pct: 40.97, total_margin_amount: 9000000, margin_masked: false }],
      error: null,
    });
    const entries = await getDashboardMarginSummary(client, { tenantId: TENANT_ID, periodStart: "2026-07-01", periodEnd: "2026-07-26" });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_org_unit_id: null,
      p_owner_user_id: null,
      p_period_start: "2026-07-01",
      p_period_end: "2026-07-26",
    });
    assert.equal(entries[0]?.avgMarginPct, 40.97);
  });
});

describe("getDashboardWinLossSummary", () => {
  test("maps outcome/currency/value", async () => {
    const { client } = recordingClient({
      data: [{ outcome: "won", currency: "IDR", opportunity_count: 1, value_amount_total: 150000000, value_masked: false }],
      error: null,
    });
    const entries = await getDashboardWinLossSummary(client, { tenantId: TENANT_ID });
    assert.equal(entries[0]?.outcome, "won");
    assert.equal(entries[0]?.valueAmountTotal, 150000000);
  });
});

describe("getDashboardForecastSummary", () => {
  test("calls get_dashboard_forecast_summary and maps weighted_value_total", async () => {
    const { client, calls } = recordingClient({
      data: [{ currency: "IDR", open_opportunity_count: 2, weighted_value_total: 130000000, value_masked: false }],
      error: null,
    });
    const entries = await getDashboardForecastSummary(client, { tenantId: TENANT_ID });
    assert.equal(calls[0]?.fn, "get_dashboard_forecast_summary");
    assert.equal(entries[0]?.weightedValueTotal, 130000000);
  });
});
