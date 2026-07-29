import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getFinanceDashboardBillingSummary,
  getFinanceDashboardCashSummary,
  getFinanceDashboardCloseStatus,
  FinanceDashboardQueryError,
  FinanceDashboardQueryTimeoutError,
  type FinanceDashboardQueryRpcClient,
} from "./finance-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const BANK_ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const PERIOD_ID = "523e4567-e89b-12d3-a456-426614174000";

function recordingClient(response: { data: unknown; error: { message: string } | null }): {
  client: FinanceDashboardQueryRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as FinanceDashboardQueryRpcClient;
  return { client, calls };
}

const BASE_FILTER = { tenantId: TENANT_ID, companyId: null, actorAuthUserId: ACTOR_ID };

describe("getFinanceDashboardBillingSummary", () => {
  test("calls get_finance_dashboard_billing_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({
      data: [{ status: "issued", currency: "USD", invoice_count: 2, total_amount: "500.00", open_amount: "300.00" }],
      error: null,
    });
    const entries = await getFinanceDashboardBillingSummary(client, BASE_FILTER);
    assert.equal(calls[0]?.fn, "get_finance_dashboard_billing_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_company_id: null, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(entries[0]?.status, "issued");
    assert.equal(entries[0]?.openAmount, 300);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View" } });
    await assert.rejects(() => getFinanceDashboardBillingSummary(client, BASE_FILTER), (err: unknown) => err instanceof FinanceDashboardQueryError);
  });

  test("rejects with a non-array result", async () => {
    const { client } = recordingClient({ data: { not: "an array" }, error: null });
    await assert.rejects(() => getFinanceDashboardBillingSummary(client, BASE_FILTER), (err: unknown) => err instanceof FinanceDashboardQueryError);
  });

  test("rejects with FinanceDashboardQueryTimeoutError once the query budget elapses", async () => {
    const client = {
      rpc() {
        return new Promise(() => {
          // Deliberately never resolves -- proves the budget timer, not the RPC, wins.
        });
      },
    } as unknown as FinanceDashboardQueryRpcClient;
    await assert.rejects(
      () => getFinanceDashboardBillingSummary(client, BASE_FILTER, { budgetMs: 10 }),
      (err: unknown) => {
        assert.ok(err instanceof FinanceDashboardQueryTimeoutError);
        assert.match((err as Error).message, /get_finance_dashboard_billing_summary/);
        return true;
      },
    );
  });
});

describe("getFinanceDashboardCashSummary", () => {
  test("calls get_finance_dashboard_cash_summary with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({
      data: [{ bank_account_id: BANK_ACCOUNT_ID, account_name: "Main Operating", currency: "USD", statement_balance: "1000.00", gl_balance: "1000.00", variance_amount: "0.00" }],
      error: null,
    });
    const entries = await getFinanceDashboardCashSummary(client, { ...BASE_FILTER, asOfDate: "2026-07-29" });
    assert.equal(calls[0]?.fn, "get_finance_dashboard_cash_summary");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_company_id: null, p_as_of_date: "2026-07-29", p_actor_auth_user_id: ACTOR_ID });
    assert.equal(entries[0]?.bankAccountId, BANK_ACCOUNT_ID);
    assert.equal(entries[0]?.varianceAmount, 0);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View" } });
    await assert.rejects(() => getFinanceDashboardCashSummary(client, { ...BASE_FILTER, asOfDate: "2026-07-29" }), (err: unknown) => err instanceof FinanceDashboardQueryError);
  });
});

describe("getFinanceDashboardCloseStatus", () => {
  test("calls get_finance_dashboard_close_status with the exact snake_case params", async () => {
    const { client, calls } = recordingClient({
      data: [
        {
          period_id: PERIOD_ID,
          period_code: "2026-07",
          period_name: "July 2026",
          end_date: "2026-07-31",
          period_status: "open",
          lock_status: null,
          reconciliation_status: null,
          reconciliation_within_tolerance: null,
        },
      ],
      error: null,
    });
    const entries = await getFinanceDashboardCloseStatus(client, BASE_FILTER);
    assert.equal(calls[0]?.fn, "get_finance_dashboard_close_status");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_company_id: null, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(entries[0]?.periodId, PERIOD_ID);
    assert.equal(entries[0]?.lockStatus, null);
  });

  test("wraps a query error", async () => {
    const { client } = recordingClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View" } });
    await assert.rejects(() => getFinanceDashboardCloseStatus(client, BASE_FILTER), (err: unknown) => err instanceof FinanceDashboardQueryError);
  });
});
