import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getFinanceLifecycleRecordState, LifecycleQueryError, type LifecycleQueryRpcClient } from "./lifecycle.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RECORD_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "423e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): LifecycleQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as LifecycleQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("getFinanceLifecycleRecordState", () => {
  test("calls app.get_finance_lifecycle_record_state with the correct arguments and parses the result", async () => {
    const client = fakeRpcClient({
      data: {
        entityType: "journal",
        recordId: RECORD_ID,
        tenantId: TENANT_ID,
        concreteStatus: "approved",
        canonicalState: "approved",
        recordVersion: 3,
        isEditable: false,
        allowedActions: ["post"],
        lockedReason: "awaiting_post",
        postedTriggerProtected: false,
      },
      error: null,
    });
    const state = await getFinanceLifecycleRecordState(client, { tenantId: TENANT_ID, entityType: "journal", recordId: RECORD_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(state.canonicalState, "approved");
    assert.deepEqual(state.allowedActions, ["post"]);
    assert.equal(client.calls[0]?.fn, "get_finance_lifecycle_record_state");
    assert.deepEqual(client.calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_entity_type: "journal",
      p_record_id: RECORD_ID,
      p_actor_auth_user_id: ACTOR_ID,
    });
  });

  test("wraps a database error into a typed LifecycleQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => getFinanceLifecycleRecordState(client, { tenantId: TENANT_ID, entityType: "journal", recordId: RECORD_ID, actorAuthUserId: ACTOR_ID }),
      LifecycleQueryError,
    );
  });

  test("throws LifecycleQueryError when no data is returned", async () => {
    const client = fakeRpcClient({ data: null, error: null });
    await assert.rejects(
      () => getFinanceLifecycleRecordState(client, { tenantId: TENANT_ID, entityType: "journal", recordId: RECORD_ID, actorAuthUserId: ACTOR_ID }),
      LifecycleQueryError,
    );
  });
});
