import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getFinanceDashboardBillingSummary,
  getFinanceDashboardReconciliationSummary,
  getFinanceDashboardCashSummary,
  FinanceDashboardQueryError,
  type FinanceDashboardQueryRpcClient,
} from "./finance-dashboard.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): FinanceDashboardQueryRpcClient {
  return { async rpc() { return response; } } as unknown as FinanceDashboardQueryRpcClient;
}

describe("getFinanceDashboardBillingSummary", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({ data: [{ status: "issued", currency: "IDR", invoice_count: "1", total_amount: "16000000.00" }], error: null });
    const rows = await getFinanceDashboardBillingSummary(client, { tenantId: TENANT_ID, companyId: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.invoiceCount, 1);
  });

  test("throws on rpc error (deny outright without FIN:View)", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: lacks FIN:View" } });
    await assert.rejects(() => getFinanceDashboardBillingSummary(client, { tenantId: TENANT_ID, companyId: null, actorAuthUserId: ACTOR_ID }), FinanceDashboardQueryError);
  });
});

describe("getFinanceDashboardReconciliationSummary", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({
      data: [{ scope: "ar", as_of_date: "2026-04-01", status: "completed", is_within_tolerance: true, variance_amount: "0.00", checked_at: "2026-04-01T00:00:00.000Z" }],
      error: null,
    });
    const rows = await getFinanceDashboardReconciliationSummary(client, { tenantId: TENANT_ID, companyId: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rows[0]?.scope, "ar");
  });
});

describe("getFinanceDashboardCashSummary", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({ data: [{ currency: "IDR", account_count: "1", statement_balance: "0.00", gl_balance: "0.00", variance_amount: "0.00" }], error: null });
    const rows = await getFinanceDashboardCashSummary(client, { tenantId: TENANT_ID, companyId: null, asOfDate: "2026-04-01", actorAuthUserId: ACTOR_ID });
    assert.equal(rows[0]?.accountCount, 1);
  });

  test("returns an empty array when no bank accounts exist", async () => {
    const client = fakeClient({ data: [], error: null });
    const rows = await getFinanceDashboardCashSummary(client, { tenantId: TENANT_ID, companyId: null, asOfDate: "2026-04-01", actorAuthUserId: ACTOR_ID });
    assert.deepEqual(rows, []);
  });
});
