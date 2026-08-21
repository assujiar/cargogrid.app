import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createAutomationRule,
  setAutomationRuleDefinition,
  dryRunAutomationRule,
  requestAutomationRulePublishApproval,
  decideAutomationRulePublishApproval,
  publishAutomationRuleVersion,
  setAutomationRuleStatus,
  AutomationRuleMutationError,
  type AutomationRuleMutationRpcClient,
} from "./automation-rule.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "423e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "623e4567-e89b-12d3-a456-426614174000";
const CONFIG_VERSION_ID = "723e4567-e89b-12d3-a456-426614174000";

const VALID_RULE_ROW = {
  id: RULE_ID,
  tenant_id: TENANT_ID,
  name: "High Priority Alert",
  description: null,
  status: "active",
  current_version_id: null,
  cooldown_seconds: 60,
  max_fires_per_window: 20,
  window_seconds: 3600,
  last_fired_at: null,
  fire_count_in_window: 0,
  record_version: 1,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
};

const VALID_VERSION_ROW = {
  id: VERSION_ID,
  automation_rule_id: RULE_ID,
  version_number: 1,
  status: "draft",
  trigger_event_type: "ticket.created",
  conditions: [],
  actions: [{ action_type: "enqueue_job", job_type: "automation_action_execution", payload: {} }],
  created_at: "2026-08-21T00:00:00.000Z",
  published_at: null,
};

const VALID_REQUEST_ROW = {
  id: REQUEST_ID,
  tenant_id: TENANT_ID,
  config_version_id: CONFIG_VERSION_ID,
  entity_type: "automation_rule_version",
  entity_id: VERSION_ID,
  pattern: "sequential",
  status: "pending",
  idempotency_key: `automation-rule-publish-${VERSION_ID}`,
  requested_by_auth_user_id: ACTOR_ID,
  requested_by: "tester",
  started_at: "2026-08-21T00:00:00.000Z",
  ended_at: null,
  ended_reason: null,
  record_version: 1,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: AutomationRuleMutationRpcClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AutomationRuleMutationRpcClient;
  return { client, calls };
}

describe("createAutomationRule", () => {
  test("calls create_automation_rule with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_RULE_ROW, error: null });
    const rule = await createAutomationRule(client, { tenantId: TENANT_ID, name: "High Priority Alert", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "create_automation_rule");
    assert.equal(calls[0]?.args.p_name, "High Priority Alert");
    assert.equal(rule.status, "active");
  });

  test("classifies insufficient_authority", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks INTHUB:Configure" } });
    await assert.rejects(
      () => createAutomationRule(client, { tenantId: TENANT_ID, name: "x", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AutomationRuleMutationError);
        assert.equal(err.code, "insufficient_authority");
        return true;
      },
    );
  });
});

describe("setAutomationRuleDefinition", () => {
  test("calls set_automation_rule_definition with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_VERSION_ROW, error: null });
    const version = await setAutomationRuleDefinition(client, {
      ruleId: RULE_ID,
      triggerEventType: "ticket.created",
      conditions: [],
      actions: [{ action_type: "enqueue_job", job_type: "automation_action_execution", payload: {} }],
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });

    assert.equal(calls[0]?.fn, "set_automation_rule_definition");
    assert.equal(calls[0]?.args.p_trigger_event_type, "ticket.created");
    assert.equal(version.triggerEventType, "ticket.created");
  });

  test("classifies automation_rule_missing_actions", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "automation_rule_missing_actions: at least one action is required" } });
    await assert.rejects(
      () => setAutomationRuleDefinition(client, { ruleId: RULE_ID, triggerEventType: "x", conditions: [], actions: [], actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AutomationRuleMutationError);
        assert.equal(err.code, "automation_rule_missing_actions");
        return true;
      },
    );
  });
});

describe("dryRunAutomationRule", () => {
  test("calls dry_run_automation_rule and returns the simulation result", async () => {
    const { client, calls } = fakeRpcClient({ data: { matched: true, trigger_event_type: "ticket.created", would_fire_actions: [] }, error: null });
    const result = await dryRunAutomationRule(client, { ruleId: RULE_ID, sampleEventPayload: { priority: "high" }, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "dry_run_automation_rule");
    assert.equal(result.matched, true);
  });
});

describe("requestAutomationRulePublishApproval", () => {
  test("calls request_automation_rule_publish_approval and returns a real pending request", async () => {
    const { client, calls } = fakeRpcClient({ data: VALID_REQUEST_ROW, error: null });
    const request = await requestAutomationRulePublishApproval(client, { ruleId: RULE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "request_automation_rule_publish_approval");
    assert.equal(request.status, "pending");
    assert.equal(request.entityId, VERSION_ID);
  });

  test("classifies automation_rule_publish_approval_not_configured", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "automation_rule_publish_approval_not_configured: tenant has not published a definition yet" } });
    await assert.rejects(
      () => requestAutomationRulePublishApproval(client, { ruleId: RULE_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AutomationRuleMutationError);
        assert.equal(err.code, "automation_rule_publish_approval_not_configured");
        return true;
      },
    );
  });
});

describe("decideAutomationRulePublishApproval", () => {
  test("calls decide_automation_rule_publish_approval with the exact snake_case params", async () => {
    const stepRow = {
      id: "823e4567-e89b-12d3-a456-426614174000",
      request_id: REQUEST_ID,
      step_order: 1,
      approver_type: "specific_user",
      role_id: null,
      specific_user_id: ACTOR_ID,
      required_approvals: 1,
      approvals_count: 1,
      status: "approved",
      created_at: "2026-08-21T00:00:00.000Z",
      updated_at: "2026-08-21T00:00:00.000Z",
    };
    const { client, calls } = fakeRpcClient({ data: stepRow, error: null });
    const step = await decideAutomationRulePublishApproval(client, { requestStepId: stepRow.id, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "decide_automation_rule_publish_approval");
    assert.equal(calls[0]?.args.p_decision, "approved");
    assert.equal(step.status, "approved");
  });

  test("classifies automation_rule_publish_approval_wrong_domain", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "automation_rule_publish_approval_wrong_domain: step does not belong to an automation rule publish request" } });
    await assert.rejects(
      () => decideAutomationRulePublishApproval(client, { requestStepId: "823e4567-e89b-12d3-a456-426614174000", decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AutomationRuleMutationError);
        assert.equal(err.code, "automation_rule_publish_approval_wrong_domain");
        return true;
      },
    );
  });
});

describe("publishAutomationRuleVersion", () => {
  test("calls publish_automation_rule_version with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_RULE_ROW, current_version_id: VERSION_ID }, error: null });
    const rule = await publishAutomationRuleVersion(client, { ruleId: RULE_ID, approvalRequestId: REQUEST_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "publish_automation_rule_version");
    assert.equal(calls[0]?.args.p_approval_request_id, REQUEST_ID);
    assert.equal(rule.currentVersionId, VERSION_ID);
  });

  test("classifies automation_rule_publish_not_approved", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "automation_rule_publish_not_approved: request is pending, not approved" } });
    await assert.rejects(
      () => publishAutomationRuleVersion(client, { ruleId: RULE_ID, approvalRequestId: REQUEST_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AutomationRuleMutationError);
        assert.equal(err.code, "automation_rule_publish_not_approved");
        return true;
      },
    );
  });
});

describe("setAutomationRuleStatus", () => {
  test("calls set_automation_rule_status with the exact snake_case params", async () => {
    const { client, calls } = fakeRpcClient({ data: { ...VALID_RULE_ROW, status: "paused" }, error: null });
    const rule = await setAutomationRuleStatus(client, { ruleId: RULE_ID, status: "paused", actorAuthUserId: ACTOR_ID, actorLabel: "tester" });

    assert.equal(calls[0]?.fn, "set_automation_rule_status");
    assert.equal(rule.status, "paused");
  });

  test("falls back to mutation_failed for an unrecognized error message", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom, unrecognized" } });
    await assert.rejects(
      () => setAutomationRuleStatus(client, { ruleId: RULE_ID, status: "paused", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }),
      (err: unknown) => {
        assert.ok(err instanceof AutomationRuleMutationError);
        assert.equal(err.code, "mutation_failed");
        return true;
      },
    );
  });
});
