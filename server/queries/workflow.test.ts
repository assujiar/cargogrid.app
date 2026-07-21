import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getWorkflowInstanceHistory, WorkflowQueryError, type WorkflowQueryRpcClient } from "./workflow.ts";

const INSTANCE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): WorkflowQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("getWorkflowInstanceHistory", () => {
  test("calls get_workflow_instance_history with the exact snake_case params and maps rows", async () => {
    const client = fakeClient({
      data: [
        {
          id: "723e4567-e89b-12d3-a456-426614174000",
          instance_id: INSTANCE_ID,
          event_type: "start",
          from_state: null,
          to_state: "draft",
          actor_auth_user_id: ACTOR_ID,
          actor_label: "tenant user",
          reason: "workflow started",
          occurred_at: "2026-07-17T00:00:00.000Z",
        },
      ],
      error: null,
    });

    const entries = await getWorkflowInstanceHistory(client, { instanceId: INSTANCE_ID, actorAuthUserId: ACTOR_ID });

    assert.deepEqual(client.calls[0]?.args, { p_instance_id: INSTANCE_ID, p_actor_auth_user_id: ACTOR_ID });
    assert.equal(entries.length, 1);
    assert.equal(entries[0]?.eventType, "start");
    assert.equal(entries[0]?.toState, "draft");
  });

  test("throws WorkflowQueryError on an rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity x is not an active member of tenant y" } });
    await assert.rejects(
      () => getWorkflowInstanceHistory(client, { instanceId: INSTANCE_ID, actorAuthUserId: ACTOR_ID }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowQueryError);
        return true;
      },
    );
  });

  test("throws WorkflowQueryError if data is not an array", async () => {
    const client = fakeClient({ data: null, error: null });
    await assert.rejects(() => getWorkflowInstanceHistory(client, { instanceId: INSTANCE_ID, actorAuthUserId: ACTOR_ID }));
  });
});
