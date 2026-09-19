import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCurrentBillingReadinessEvaluation, getBillingReadinessEvaluationHistory, listBillingReadinessHandoffs, type BillingReadinessQueryClient } from "./billing-readiness.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVAL_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "723e4567-e89b-12d3-a456-426614174000";

const EVALUATION_ROW = {
  id: EVAL_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  version_number: 1,
  is_current: true,
  evaluated_status: "ready",
  effective_status: "ready",
  blockers: [],
  evidence: { shipmentOrderIds: [], actualCostIds: [], epodCaptureIds: [], creditOutcome: "allow", jobOrderStatus: "confirmed" },
  rule_version: 1,
  is_overridden: false,
  override_reason: null,
  overridden_by: null,
  overridden_at: null,
  override_revoked_reason: null,
  override_revoked_by: null,
  override_revoked_at: null,
  reevaluation_reason: null,
  supersedes_evaluation_id: null,
  evaluated_by_auth_user_id: ACTOR_ID,
  evaluated_by: "rep",
  record_version: 1,
  created_by: "rep",
  created_at: "2026-07-28T09:00:00.000Z",
  updated_at: "2026-07-28T09:00:00.000Z",
};

const HANDOFF_ROW = {
  id: HANDOFF_ID,
  tenant_id: TENANT_ID,
  job_order_id: JOB_ORDER_ID,
  evaluation_id: EVAL_ID,
  idempotency_key: "idem-handoff-1",
  handed_off_by_auth_user_id: ACTOR_ID,
  handed_off_by: "rep",
  handed_off_at: "2026-07-28T11:00:00.000Z",
  created_at: "2026-07-28T11:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }, capture: { calls: Record<string, unknown> }): BillingReadinessQueryClient {
  const fake = {
    async rpc(fn: string, args: Record<string, unknown>) {
      capture.calls.fn = fn;
      capture.calls.args = args;
      return response;
    },
  };
  return fake as unknown as BillingReadinessQueryClient;
}

describe("getCurrentBillingReadinessEvaluation", () => {
  test("calls get_current_billing_readiness_evaluation with job_order_id/actor, returns the parsed row", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [EVALUATION_ROW], error: null }, capture);
    const row = await getCurrentBillingReadinessEvaluation(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "get_current_billing_readiness_evaluation");
    assert.deepEqual(capture.calls.args, { p_job_order_id: JOB_ORDER_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(row?.id, EVAL_ID);
  });

  test("returns null when the Job Order has never been evaluated", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [], error: null }, capture);
    const row = await getCurrentBillingReadinessEvaluation(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(row, null);
  });
});

describe("getBillingReadinessEvaluationHistory", () => {
  test("calls list_billing_readiness_evaluations with job_order_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [EVALUATION_ROW], error: null }, capture);
    const history = await getBillingReadinessEvaluationHistory(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_billing_readiness_evaluations");
    assert.deepEqual(capture.calls.args, { p_job_order_id: JOB_ORDER_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(history.length, 1);
  });
});

describe("listBillingReadinessHandoffs", () => {
  test("calls list_billing_readiness_handoffs with job_order_id/actor", async () => {
    const capture = { calls: {} as Record<string, unknown> };
    const client = fakeRpcClient({ data: [HANDOFF_ROW], error: null }, capture);
    const handoffs = await listBillingReadinessHandoffs(client, JOB_ORDER_ID, ACTOR_ID);
    assert.equal(capture.calls.fn, "list_billing_readiness_handoffs");
    assert.deepEqual(capture.calls.args, { p_job_order_id: JOB_ORDER_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(handoffs[0]?.id, HANDOFF_ID);
  });
});
