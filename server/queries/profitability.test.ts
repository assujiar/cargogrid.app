import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getFinanceJobProfitability, getFinanceProfitabilitySummary, ProfitabilityQueryError, type ProfitabilityQueryRpcClient } from "./profitability.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const FACT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): ProfitabilityQueryRpcClient {
  return { async rpc() { return response; } } as unknown as ProfitabilityQueryRpcClient;
}

describe("getFinanceJobProfitability", () => {
  test("maps the current fact row", async () => {
    const client = fakeClient({
      data: [{
        id: FACT_ID, tenant_id: TENANT_ID, job_order_id: JOB_ID, version_number: 1, is_current: true,
        status: "calculated", blocked_reason: null, revenue_basis: "billed",
        revenue_currency: "IDR", revenue_amount: "15000000.00", cost_currency: "IDR", cost_amount: "9000000.00",
        profit_amount: "6000000.00", margin_percent: "40.0000",
        source_invoice_ids: [], source_cost_version_ids: [],
        recalculation_reason: null, calculated_by_auth_user_id: ACTOR_ID, calculated_at: "2026-07-01T00:00:00.000Z",
        record_version: 1, created_by: "financemanagera", created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
      }],
      error: null,
    });
    const rows = await getFinanceJobProfitability(client, { jobOrderId: JOB_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.profitAmount, 6000000);
  });

  test("returns an empty array when never calculated", async () => {
    const client = fakeClient({ data: [], error: null });
    const rows = await getFinanceJobProfitability(client, { jobOrderId: JOB_ID, actorAuthUserId: ACTOR_ID });
    assert.deepEqual(rows, []);
  });

  test("throws on rpc error (deny outright without FIN:View margin)", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: lacks FIN:View margin" } });
    await assert.rejects(() => getFinanceJobProfitability(client, { jobOrderId: JOB_ID, actorAuthUserId: ACTOR_ID }), ProfitabilityQueryError);
  });
});

describe("getFinanceProfitabilitySummary", () => {
  test("maps grouped summary rows", async () => {
    const client = fakeClient({
      data: [{
        dimension_key: "acct-1", dimension_label: "Customer One Logistics", currency: "IDR",
        job_count: "2", revenue_amount: "25000000.00", cost_amount: "15000000.00", profit_amount: "10000000.00", margin_percent: "40.0000",
      }],
      error: null,
    });
    const rows = await getFinanceProfitabilitySummary(client, { tenantId: TENANT_ID, groupBy: "customer", actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.jobCount, 2);
  });

  test("throws on rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_profitability_invalid_group_by: region is not a supported grouping dimension" } });
    await assert.rejects(() => getFinanceProfitabilitySummary(client, { tenantId: TENANT_ID, groupBy: "region", actorAuthUserId: ACTOR_ID }), ProfitabilityQueryError);
  });
});
