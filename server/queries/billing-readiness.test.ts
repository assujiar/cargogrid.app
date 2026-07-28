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

function fakeClient(response: { data: unknown; error: { message: string } | null }): {
  client: BillingReadinessQueryClient;
  calls: { table: string; eqs: [string, unknown][]; order: [string, unknown] | null }[];
} {
  const calls: { table: string; eqs: [string, unknown][]; order: [string, unknown] | null }[] = [];
  const client = {
    from(table: string) {
      const eqs: [string, unknown][] = [];
      let orderCall: [string, unknown] | null = null;
      const builder = {
        select() {
          return builder;
        },
        eq(column: string, value: unknown) {
          eqs.push([column, value]);
          return builder;
        },
        order(column: string, opts: unknown) {
          orderCall = [column, opts];
          calls.push({ table, eqs, order: orderCall });
          return Promise.resolve(response);
        },
        async maybeSingle() {
          calls.push({ table, eqs, order: null });
          return response;
        },
      };
      return builder;
    },
  } as unknown as BillingReadinessQueryClient;
  return { client, calls };
}

describe("getCurrentBillingReadinessEvaluation", () => {
  test("filters by job_order_id and is_current, returns the parsed row", async () => {
    const { client, calls } = fakeClient({ data: EVALUATION_ROW, error: null });
    const row = await getCurrentBillingReadinessEvaluation(client, JOB_ORDER_ID);
    assert.equal(calls[0]?.table, "billing_readiness_evaluations");
    assert.deepEqual(calls[0]?.eqs, [
      ["job_order_id", JOB_ORDER_ID],
      ["is_current", true],
    ]);
    assert.equal(row?.id, EVAL_ID);
  });

  test("returns null when the Job Order has never been evaluated", async () => {
    const { client } = fakeClient({ data: null, error: null });
    const row = await getCurrentBillingReadinessEvaluation(client, JOB_ORDER_ID);
    assert.equal(row, null);
  });
});

describe("getBillingReadinessEvaluationHistory", () => {
  test("orders by version_number ascending", async () => {
    const { client, calls } = fakeClient({ data: [EVALUATION_ROW], error: null });
    const history = await getBillingReadinessEvaluationHistory(client, JOB_ORDER_ID);
    assert.equal(calls[0]?.table, "billing_readiness_evaluations");
    assert.deepEqual(calls[0]?.order, ["version_number", { ascending: true }]);
    assert.equal(history.length, 1);
  });
});

describe("listBillingReadinessHandoffs", () => {
  test("orders by handed_off_at descending", async () => {
    const { client, calls } = fakeClient({ data: [HANDOFF_ROW], error: null });
    const handoffs = await listBillingReadinessHandoffs(client, JOB_ORDER_ID);
    assert.equal(calls[0]?.table, "billing_readiness_handoffs");
    assert.deepEqual(calls[0]?.order, ["handed_off_at", { ascending: false }]);
    assert.equal(handoffs[0]?.id, HANDOFF_ID);
  });
});
