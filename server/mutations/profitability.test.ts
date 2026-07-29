import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { calculateFinanceJobProfitability, ProfitabilityMutationError, type ProfitabilityMutationRpcClient } from "./profitability.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const FACT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const FACT_ROW = {
  id: FACT_ID, tenant_id: TENANT_ID, job_order_id: JOB_ID, version_number: 1, is_current: true,
  status: "calculated", blocked_reason: null, revenue_basis: "billed",
  revenue_currency: "IDR", revenue_amount: "15000000.00", cost_currency: "IDR", cost_amount: "9000000.00",
  profit_amount: "6000000.00", margin_percent: "40.0000",
  source_invoice_ids: [], source_cost_version_ids: [],
  recalculation_reason: null, calculated_by_auth_user_id: ACTOR_ID, calculated_at: "2026-07-01T00:00:00.000Z",
  record_version: 1, created_by: "financemanagera", created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): ProfitabilityMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as ProfitabilityMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("calculateFinanceJobProfitability", () => {
  test("calls calculate_finance_job_profitability with exact snake_case params, reason defaulting to null", async () => {
    const client = fakeClient({ data: FACT_ROW, error: null });
    const fact = await calculateFinanceJobProfitability(client, { jobOrderId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera" });
    assert.equal(client.calls[0]?.fn, "calculate_finance_job_profitability");
    assert.equal(client.calls[0]?.args.p_recalculation_reason, null);
    assert.equal(fact.profitAmount, 6000000);
    assert.equal(fact.marginPercent, 40);
  });

  test("passes an explicit recalculation reason through", async () => {
    const client = fakeClient({ data: { ...FACT_ROW, version_number: 2 }, error: null });
    await calculateFinanceJobProfitability(client, { jobOrderId: JOB_ID, recalculationReason: "fixture: recalculating", actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera" });
    assert.equal(client.calls[0]?.args.p_recalculation_reason, "fixture: recalculating");
  });

  test("wraps a finance_profitability_recalculation_reason_required error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_profitability_recalculation_reason_required: a reason is required to recalculate an existing profitability fact" } });
    await assert.rejects(
      () => calculateFinanceJobProfitability(client, { jobOrderId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "financemanagera" }),
      (error: unknown) => error instanceof ProfitabilityMutationError && error.code === "finance_profitability_recalculation_reason_required",
    );
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View margin for tenant" } });
    await assert.rejects(
      () => calculateFinanceJobProfitability(client, { jobOrderId: JOB_ID, actorAuthUserId: ACTOR_ID, actorLabel: "financeeditora" }),
      (error: unknown) => error instanceof ProfitabilityMutationError && error.code === "insufficient_authority",
    );
  });
});
