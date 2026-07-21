import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseWorkflowHook,
  parseWorkflowInstance,
  parseWorkflowTransitionHistoryEntry,
  RegisterWorkflowHookInputSchema,
  StartWorkflowInstanceInputSchema,
} from "./workflow.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";
const INSTANCE_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseWorkflowHook", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const hook = parseWorkflowHook({
      code: "always_true",
      hook_type: "guard",
      name: "Always True",
      description: "Unconditionally permits the transition.",
      registered_by: "platform-core-foundation",
      created_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(hook.hookType, "guard");
    assert.equal(hook.registeredBy, "platform-core-foundation");
  });
});

describe("parseWorkflowInstance", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const instance = parseWorkflowInstance({
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
    });
    assert.equal(instance.status, "active");
    assert.equal(instance.currentState, "draft");
    assert.equal(instance.configVersionId, VERSION_ID);
  });
});

describe("parseWorkflowTransitionHistoryEntry", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const entry = parseWorkflowTransitionHistoryEntry({
      id: "723e4567-e89b-12d3-a456-426614174000",
      instance_id: INSTANCE_ID,
      event_type: "transition",
      from_state: "draft",
      to_state: "submitted",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "tenant user",
      reason: null,
      occurred_at: "2026-07-17T00:00:00.000Z",
    });
    assert.equal(entry.eventType, "transition");
    assert.equal(entry.fromState, "draft");
    assert.equal(entry.toState, "submitted");
  });
});

describe("RegisterWorkflowHookInputSchema", () => {
  test("defaults description to null", () => {
    const parsed = RegisterWorkflowHookInputSchema.parse({
      code: "always_true",
      hookType: "guard",
      name: "Always True",
      actorAuthUserId: ACTOR_ID,
      registeredBy: "tester",
    });
    assert.equal(parsed.description, null);
  });

  test("rejects an unknown hookType", () => {
    assert.throws(() =>
      RegisterWorkflowHookInputSchema.parse({
        code: "x",
        hookType: "trigger",
        name: "X",
        actorAuthUserId: ACTOR_ID,
        registeredBy: "tester",
      }),
    );
  });
});

describe("StartWorkflowInstanceInputSchema", () => {
  test("defaults entityType to generic and entityId to null", () => {
    const parsed = StartWorkflowInstanceInputSchema.parse({
      configVersionId: VERSION_ID,
      tenantId: TENANT_ID,
      idempotencyKey: "quote-9001",
      actorAuthUserId: ACTOR_ID,
      startedBy: "tenant user",
    });
    assert.equal(parsed.entityType, "generic");
    assert.equal(parsed.entityId, null);
  });
});
