import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  evaluateBillingReadiness,
  overrideBillingReadiness,
  revokeBillingReadinessOverride,
  handoffBillingReadiness,
  BillingReadinessMutationError,
  type BillingReadinessMutationRpcClient,
} from "./billing-readiness.ts";

const JOB_ORDER_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVAL_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
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

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: BillingReadinessMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as BillingReadinessMutationRpcClient;
  return { client, calls };
}

describe("evaluateBillingReadiness", () => {
  test("calls evaluate_billing_readiness with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: EVALUATION_ROW, error: null });
    const evaluation = await evaluateBillingReadiness(client, { jobOrderId: JOB_ORDER_ID, reevaluationReason: null, actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "evaluate_billing_readiness");
    assert.deepEqual(calls[0]?.args, { p_job_order_id: JOB_ORDER_ID, p_reevaluation_reason: null, p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(evaluation.evaluatedStatus, "ready");
  });

  test("classifies billing_readiness_reevaluation_reason_required", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "billing_readiness_reevaluation_reason_required: a non-empty reason is required" } });
    await assert.rejects(
      () => evaluateBillingReadiness(client, { jobOrderId: JOB_ORDER_ID, actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof BillingReadinessMutationError);
        assert.equal(err.code, "billing_readiness_reevaluation_reason_required");
        return true;
      },
    );
  });
});

describe("overrideBillingReadiness", () => {
  test("calls override_billing_readiness with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...EVALUATION_ROW, evaluated_status: "not_ready", effective_status: "ready", is_overridden: true, override_reason: "priority customer" }, error: null });
    const evaluation = await overrideBillingReadiness(client, { jobOrderId: JOB_ORDER_ID, expectedVersion: 1, reason: "priority customer", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "override_billing_readiness");
    assert.deepEqual(calls[0]?.args, { p_job_order_id: JOB_ORDER_ID, p_expected_version: 1, p_reason: "priority customer", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(evaluation.effectiveStatus, "ready");
    assert.equal(evaluation.evaluatedStatus, "not_ready");
  });

  test("classifies billing_readiness_override_not_needed", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "billing_readiness_override_not_needed: job order is already effectively ready" } });
    await assert.rejects(
      () => overrideBillingReadiness(client, { jobOrderId: JOB_ORDER_ID, expectedVersion: 1, reason: "redundant", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof BillingReadinessMutationError);
        assert.equal(err.code, "billing_readiness_override_not_needed");
        return true;
      },
    );
  });
});

describe("revokeBillingReadinessOverride", () => {
  test("calls revoke_billing_readiness_override with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...EVALUATION_ROW, evaluated_status: "not_ready", effective_status: "not_ready", is_overridden: false, override_reason: "priority customer", override_revoked_reason: "disputed" }, error: null });
    const evaluation = await revokeBillingReadinessOverride(client, { jobOrderId: JOB_ORDER_ID, expectedVersion: 2, reason: "disputed", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "revoke_billing_readiness_override");
    assert.deepEqual(calls[0]?.args, { p_job_order_id: JOB_ORDER_ID, p_expected_version: 2, p_reason: "disputed", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(evaluation.effectiveStatus, "not_ready");
    assert.equal(evaluation.overrideReason, "priority customer");
  });

  test("classifies billing_readiness_not_overridden", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "billing_readiness_not_overridden: no active override to revoke" } });
    await assert.rejects(
      () => revokeBillingReadinessOverride(client, { jobOrderId: JOB_ORDER_ID, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof BillingReadinessMutationError);
        assert.equal(err.code, "billing_readiness_not_overridden");
        return true;
      },
    );
  });
});

describe("handoffBillingReadiness", () => {
  test("calls handoff_billing_readiness with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({
      data: { id: HANDOFF_ID, tenant_id: TENANT_ID, job_order_id: JOB_ORDER_ID, evaluation_id: EVAL_ID, idempotency_key: "idem-1", handed_off_by_auth_user_id: ACTOR_ID, handed_off_by: "rep", handed_off_at: "2026-07-28T11:00:00.000Z", created_at: "2026-07-28T11:00:00.000Z" },
      error: null,
    });
    const handoff = await handoffBillingReadiness(client, { jobOrderId: JOB_ORDER_ID, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(calls[0]?.fn, "handoff_billing_readiness");
    assert.deepEqual(calls[0]?.args, { p_job_order_id: JOB_ORDER_ID, p_idempotency_key: "idem-1", p_actor_auth_user_id: ACTOR_ID, p_actor_label: "rep" });
    assert.equal(handoff.id, HANDOFF_ID);
  });

  test("classifies billing_readiness_not_ready", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "billing_readiness_not_ready: job order is not effectively ready for billing handoff" } });
    await assert.rejects(
      () => handoffBillingReadiness(client, { jobOrderId: JOB_ORDER_ID, idempotencyKey: "idem-2", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
      (err: unknown) => {
        assert.ok(err instanceof BillingReadinessMutationError);
        assert.equal(err.code, "billing_readiness_not_ready");
        return true;
      },
    );
  });
});
