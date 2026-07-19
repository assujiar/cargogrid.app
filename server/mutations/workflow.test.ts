import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  registerWorkflowHook,
  publishWorkflowDefinition,
  startWorkflowInstance,
  transitionWorkflowInstance,
  cancelWorkflowInstance,
  WorkflowMutationError,
  type WorkflowMutationRpcClient,
} from "./workflow.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const OBJECT_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const INSTANCE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

const VALID_HOOK_ROW = {
  code: "always_true",
  hook_type: "guard",
  name: "Always True",
  description: "Unconditionally permits the transition.",
  registered_by: "platform-core-foundation",
  created_at: "2026-07-17T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  config_object_id: OBJECT_ID,
  version_number: 1,
  status: "published",
  effective_from: "2026-07-17T00:00:00.000Z",
  effective_to: null,
  cloned_from_version_id: null,
  rollback_of_version_id: null,
  created_by: "tenant admin",
  published_by: "tenant admin",
  published_at: "2026-07-17T00:00:00.000Z",
  archived_at: null,
  archived_reason: null,
  record_version: 2,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

const VALID_INSTANCE_ROW = {
  id: INSTANCE_ID,
  tenant_id: TENANT_ID,
  config_version_id: VERSION_ID,
  entity_type: "generic",
  entity_id: null,
  current_state: "draft",
  status: "active",
  idempotency_key: "quote-9001",
  started_by: "tenant user",
  started_at: "2026-07-17T00:00:00.000Z",
  ended_at: null,
  ended_reason: null,
  record_version: 1,
  created_at: "2026-07-17T00:00:00.000Z",
  updated_at: "2026-07-17T00:00:00.000Z",
};

function fakeClient(
  response: { data: unknown; error: { message: string } | null },
): WorkflowMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn, args) {
      calls.push({ fn, args });
      return response;
    },
  };
}

describe("registerWorkflowHook", () => {
  test("calls register_workflow_hook with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_HOOK_ROW, error: null });
    await registerWorkflowHook(client, { code: "always_true", hookType: "guard", name: "Always True", description: "d", actorAuthUserId: ACTOR_ID, registeredBy: "tester" });

    assert.deepEqual(client.calls[0]?.args, {
      p_code: "always_true",
      p_hook_type: "guard",
      p_name: "Always True",
      p_description: "d",
      p_actor_auth_user_id: ACTOR_ID,
      p_registered_by: "tester",
    });
  });

  test("wraps an insufficient_authority error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: only Supreme Admin may register a workflow hook" } });
    await assert.rejects(
      () => registerWorkflowHook(client, { code: "x", hookType: "guard", name: "X", actorAuthUserId: ACTOR_ID, registeredBy: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("publishWorkflowDefinition", () => {
  test("calls publish_workflow_definition and returns the published version row", async () => {
    const client = fakeClient({ data: VALID_VERSION_ROW, error: null });
    const version = await publishWorkflowDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" });
    assert.equal(version.status, "published");
    assert.equal(client.calls[0]?.fn, "publish_workflow_definition");
  });

  test("wraps a workflow_unreachable_state error", async () => {
    const client = fakeClient({ data: null, error: { message: "workflow_unreachable_state: 1 declared state(s) are unreachable from initial_state draft" } });
    await assert.rejects(
      () => publishWorkflowDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowMutationError);
        assert.equal(err.code, "workflow_unreachable_state");
        return true;
      },
    );
  });

  test("wraps a workflow_dead_end_state error", async () => {
    const client = fakeClient({ data: null, error: { message: "workflow_dead_end_state: non-terminal state submitted has no outgoing transition" } });
    await assert.rejects(
      () => publishWorkflowDefinition(client, { versionId: VERSION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant admin" }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowMutationError);
        assert.equal(err.code, "workflow_dead_end_state");
        return true;
      },
    );
  });
});

describe("startWorkflowInstance", () => {
  test("calls start_workflow_instance with the exact snake_case params", async () => {
    const client = fakeClient({ data: VALID_INSTANCE_ROW, error: null });
    const instance = await startWorkflowInstance(client, {
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      entityType: "generic",
      entityId: null,
      idempotencyKey: "quote-9001",
      actorAuthUserId: ACTOR_ID,
      startedBy: "tenant user",
    });

    assert.deepEqual(client.calls[0]?.args, {
      p_config_version_id: VERSION_ID,
      p_tenant_id: TENANT_ID,
      p_entity_type: "generic",
      p_entity_id: null,
      p_idempotency_key: "quote-9001",
      p_actor_auth_user_id: ACTOR_ID,
      p_started_by: "tenant user",
    });
    assert.equal(instance.currentState, "draft");
  });

  test("wraps a workflow_definition_not_published error", async () => {
    const client = fakeClient({ data: null, error: { message: "workflow_definition_not_published: config version x is not a published workflow definition" } });
    await assert.rejects(
      () =>
        startWorkflowInstance(client, {
          configVersionId: VERSION_ID,
          tenantId: TENANT_ID,
          idempotencyKey: "quote-9001",
          actorAuthUserId: ACTOR_ID,
          startedBy: "tenant user",
        }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowMutationError);
        assert.equal(err.code, "workflow_definition_not_published");
        return true;
      },
    );
  });
});

describe("transitionWorkflowInstance", () => {
  test("calls transition_workflow_instance and returns the updated instance", async () => {
    const transitionedRow = { ...VALID_INSTANCE_ROW, current_state: "submitted" };
    const client = fakeClient({ data: transitionedRow, error: null });
    const instance = await transitionWorkflowInstance(client, {
      instanceId: INSTANCE_ID,
      expectedCurrentState: "draft",
      toState: "submitted",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tenant user",
    });
    assert.equal(instance.currentState, "submitted");
  });

  test("wraps a stale_workflow_state error", async () => {
    const client = fakeClient({ data: null, error: { message: "stale_workflow_state: expected state draft but instance x is at state submitted" } });
    await assert.rejects(
      () =>
        transitionWorkflowInstance(client, {
          instanceId: INSTANCE_ID,
          expectedCurrentState: "draft",
          toState: "submitted",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tenant user",
        }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowMutationError);
        assert.equal(err.code, "stale_workflow_state");
        return true;
      },
    );
  });

  test("wraps a workflow_guard_rejected error", async () => {
    const client = fakeClient({ data: null, error: { message: "workflow_guard_rejected: guard some_guard rejected transition draft -> submitted" } });
    await assert.rejects(
      () =>
        transitionWorkflowInstance(client, {
          instanceId: INSTANCE_ID,
          expectedCurrentState: "draft",
          toState: "submitted",
          actorAuthUserId: ACTOR_ID,
          actorLabel: "tenant user",
        }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowMutationError);
        assert.equal(err.code, "workflow_guard_rejected");
        return true;
      },
    );
  });
});

describe("cancelWorkflowInstance", () => {
  test("calls cancel_workflow_instance with the exact snake_case params", async () => {
    const cancelledRow = { ...VALID_INSTANCE_ROW, status: "cancelled", ended_reason: "duplicate request" };
    const client = fakeClient({ data: cancelledRow, error: null });
    const instance = await cancelWorkflowInstance(client, { instanceId: INSTANCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user", reason: "duplicate request" });

    assert.deepEqual(client.calls[0]?.args, {
      p_instance_id: INSTANCE_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_actor_label: "tenant user",
      p_reason: "duplicate request",
    });
    assert.equal(instance.status, "cancelled");
  });

  test("wraps a workflow_instance_not_active error", async () => {
    const client = fakeClient({ data: null, error: { message: "workflow_instance_not_active: instance x is completed, only an active instance may be cancelled" } });
    await assert.rejects(
      () => cancelWorkflowInstance(client, { instanceId: INSTANCE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tenant user", reason: null }),
      (err: unknown) => {
        assert.ok(err instanceof WorkflowMutationError);
        assert.equal(err.code, "workflow_instance_not_active");
        return true;
      },
    );
  });
});
