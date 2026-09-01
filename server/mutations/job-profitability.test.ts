import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { calculateJobProfitability, JobProfitabilityMutationError, type JobProfitabilityMutationRpcClient } from "./job-profitability.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const SNAPSHOT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: JobProfitabilityMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as JobProfitabilityMutationRpcClient;
  return { client, calls };
}

const SNAPSHOT_ROW = {
  id: SNAPSHOT_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  version_number: 1,
  is_current: true,
  status: "calculated",
  blocked_reason: null,
  revenue_basis: "quoted",
  revenue_currency: "IDR",
  revenue_amount: 15000000,
  cost_currency: "IDR",
  cost_amount: 8000000,
  margin_amount: 7000000,
  margin_percent: 46.6667,
  source_cost_version_ids: [SNAPSHOT_ID],
  recalculation_reason: null,
  calculated_by_auth_user_id: ACTOR_ID,
  calculated_at: "2026-07-28T09:00:00.000Z",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

describe("calculateJobProfitability", () => {
  test("calls calculate_job_profitability with the exact snake_case params, defaulting recalculationReason to null", async () => {
    const { client, calls } = fakeRpcClient({ data: SNAPSHOT_ROW, error: null });
    const snapshot = await calculateJobProfitability(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "calculate_job_profitability");
    assert.deepEqual(calls[0]?.args, {
      p_job_order_id: JOB_ORDER_ID,
      p_recalculation_reason: null,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "rep",
    });
    assert.equal(snapshot.marginAmount, 7000000);
  });

  test("classifies job_profitability_recalculation_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "job_profitability_recalculation_reason_required: a reason is required" } });
    await assert.rejects(
      () => calculateJobProfitability(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof JobProfitabilityMutationError);
        assert.equal(err.code, "job_profitability_recalculation_reason_required");
        return true;
      },
    );
  });

  test("classifies insufficient_authority for an actor lacking OPS:View margin", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks OPS:View margin" } });
    await assert.rejects(
      () => calculateJobProfitability(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "restricted" }),
      (err: unknown) => {
        assert.ok(err instanceof JobProfitabilityMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});
