import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getApprovalRequestHistory, listPendingApprovalStepsForActor, ApprovalQueryError, type ApprovalQueryRpcClient } from "./approval.ts";

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
