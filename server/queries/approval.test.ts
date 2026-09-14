import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getApprovalRequestHistory, listPendingApprovalStepsForActor, getApprovalRequestStep, getApprovalRequestById, ApprovalQueryError, type ApprovalQueryRpcClient } from "./approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";
const ROLE_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): ApprovalQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("getApprovalRequestHistory", () => {
  test("calls get_approval_request_history with the exact snake_case params and maps rows", async () => {
    const client = fakeClient({
      data: [
        {
          step_id: STEP_ID,
          step_order: 1,
          approver_type: "role",
          step_status: "approved",
          decision_id: "a23e4567-e89b-12d3-a456-426614174000",
          actor_auth_user_id: ACTOR_ID,
          actor_label: "manager",
          decision: "approved",
          reason: null,
          decided_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });

    const entries = await getApprovalRequestHistory(client, { requestId: REQUEST_ID, actorAuthUserId: ACTOR_ID });

    assert.deepEqual(client.calls[0]?.args, { p_request_id: REQUEST_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(entries.length, 1);
    assert.equal(entries[0]?.decision, "approved");
  });

  test("throws ApprovalQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x is not an active member of tenant y" } });
    await assert.rejects(() => getApprovalRequestHistory(client, { requestId: REQUEST_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("listPendingApprovalStepsForActor", () => {
  test("calls list_pending_approval_steps_for_actor with the exact snake_case params and maps rows", async () => {
    const client = fakeClient({
      data: [
        {
          id: STEP_ID,
          request_id: REQUEST_ID,
          step_order: 1,
          approver_type: "role",
          role_id: ROLE_ID,
          specific_user_id: null,
          required_approvals: 1,
          approvals_count: 0,
          status: "active",
          created_at: "2026-07-19T00:00:00.000Z",
          updated_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });

    const steps = await listPendingApprovalStepsForActor(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID });

    assert.deepEqual(client.calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(steps.length, 1);
    assert.equal(steps[0]?.status, "active");
  });

  test("throws ApprovalQueryError if data is not an array", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(() => listPendingApprovalStepsForActor(client, { tenantId: TENANT_ID, actorAuthUserId: ACTOR_ID }));
  });
});

describe("getApprovalRequestStep", () => {
  test("resolves a matched step by id", async () => {
    const client = fakeClient({
      data: [
        {
          id: STEP_ID,
          request_id: REQUEST_ID,
          step_order: 1,
          approver_type: "role",
          role_id: ROLE_ID,
          specific_user_id: null,
          required_approvals: 1,
          approvals_count: 0,
          status: "active",
          created_at: "2026-07-19T00:00:00.000Z",
          updated_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });

    const step = await getApprovalRequestStep(client, STEP_ID);

    assert.equal(client.calls[0]?.fn, "get_approval_request_step");
    assert.deepEqual(client.calls[0]?.args, { p_step_id: STEP_ID });
    assert.equal(step?.requestId, REQUEST_ID);
  });

  test("returns null (never an error) when not found", async () => {
    const client = fakeClient({ data: [], error: null });
    const step = await getApprovalRequestStep(client, STEP_ID);
    assert.equal(step, null);
  });

  test("throws ApprovalQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => getApprovalRequestStep(client, STEP_ID), ApprovalQueryError);
  });
});

describe("getApprovalRequestById", () => {
  test("resolves a matched request by id, with ended_reason genuinely nulled", async () => {
    const client = fakeClient({
      data: [
        {
          id: REQUEST_ID,
          tenant_id: TENANT_ID,
          config_version_id: "923e4567-e89b-12d3-a456-426614174000",
          entity_type: "procurement_approval_policy",
          entity_id: null,
          pattern: "sequential",
          status: "pending",
          idempotency_key: "idem-1",
          requested_by_auth_user_id: ACTOR_ID,
          requested_by: "tester",
          started_at: "2026-07-19T00:00:00.000Z",
          ended_at: null,
          ended_reason: null,
          record_version: 1,
          created_at: "2026-07-19T00:00:00.000Z",
          updated_at: "2026-07-19T00:00:00.000Z",
        },
      ],
      error: null,
    });

    const request = await getApprovalRequestById(client, REQUEST_ID);

    assert.equal(client.calls[0]?.fn, "get_approval_request_by_id");
    assert.deepEqual(client.calls[0]?.args, { p_request_id: REQUEST_ID });
    assert.equal(request?.status, "pending");
    assert.equal(request?.endedReason, null);
  });

  test("returns null (never an error) when not found", async () => {
    const client = fakeClient({ data: [], error: null });
    const request = await getApprovalRequestById(client, REQUEST_ID);
    assert.equal(request, null);
  });

  test("throws ApprovalQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "connection reset" } });
    await assert.rejects(() => getApprovalRequestById(client, REQUEST_ID), ApprovalQueryError);
  });
});
