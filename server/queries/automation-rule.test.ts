import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listAutomationRules,
  getAutomationRuleById,
  listAutomationRuleVersions,
  listAutomationRuleExecutions,
  getLatestAutomationRulePublishApprovalRequest,
  listApprovalRequestSteps,
  AutomationRuleQueryError,
  type AutomationRuleQueryClient,
} from "./automation-rule.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";

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
  trigger_event_type: null,
  conditions: [],
  actions: [],
  created_at: "2026-08-21T00:00:00.000Z",
  published_at: null,
};

const VALID_EXECUTION_ROW = {
  id: "523e4567-e89b-12d3-a456-426614174000",
  automation_rule_id: RULE_ID,
  automation_rule_version_id: VERSION_ID,
  trigger_event_type: "ticket.created",
  source_event_id: null,
  event_payload: {},
  status: "completed",
  suppressed_reason: null,
  actions_taken: [],
  executed_at: "2026-08-21T00:00:00.000Z",
};

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: AutomationRuleQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown> = {}) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as AutomationRuleQueryClient;
  return { client, calls };
}

describe("listAutomationRules", () => {
  test("calls list_automation_rules and maps rule rows", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_RULE_ROW], error: null });
    const rules = await listAutomationRules(client, TENANT_ID);
    assert.equal(calls[0]?.fn, "list_automation_rules");
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID });
    assert.equal(rules.length, 1);
    assert.equal(rules[0]?.name, "High Priority Alert");
  });

  test("wraps a query error", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "boom" } });
    await assert.rejects(
      () => listAutomationRules(client, TENANT_ID),
      (err: unknown) => err instanceof AutomationRuleQueryError,
    );
  });
});

describe("getAutomationRuleById", () => {
  test("returns null (never an error) when not found", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const rule = await getAutomationRuleById(client, RULE_ID);
    assert.equal(rule, null);
  });

  test("parses a matched row", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_RULE_ROW], error: null });
    const rule = await getAutomationRuleById(client, RULE_ID);
    assert.deepEqual(calls[0]?.args, { p_rule_id: RULE_ID });
    assert.equal(rule?.id, RULE_ID);
  });
});

describe("listAutomationRuleVersions", () => {
  test("calls list_automation_rule_versions and maps version rows, newest first", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_VERSION_ROW], error: null });
    const versions = await listAutomationRuleVersions(client, RULE_ID);
    assert.deepEqual(calls[0]?.args, { p_automation_rule_id: RULE_ID });
    assert.equal(versions.length, 1);
    assert.equal(versions[0]?.status, "draft");
  });
});

describe("listAutomationRuleExecutions", () => {
  test("calls list_automation_rule_executions and maps execution rows, newest first", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_EXECUTION_ROW], error: null });
    const executions = await listAutomationRuleExecutions(client, RULE_ID);
    assert.deepEqual(calls[0]?.args, { p_automation_rule_id: RULE_ID, p_limit: 25 });
    assert.equal(executions.length, 1);
    assert.equal(executions[0]?.status, "completed");
  });
});

const VALID_APPROVAL_REQUEST_ROW = {
  id: "623e4567-e89b-12d3-a456-426614174000",
  tenant_id: TENANT_ID,
  config_version_id: "723e4567-e89b-12d3-a456-426614174000",
  entity_type: "automation_rule_version",
  entity_id: VERSION_ID,
  pattern: "sequential",
  status: "pending",
  idempotency_key: `automation-rule-publish-${VERSION_ID}`,
  requested_by_auth_user_id: null,
  requested_by: "tester",
  started_at: "2026-08-21T00:00:00.000Z",
  ended_at: null,
  ended_reason: null,
  record_version: 1,
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
};

const VALID_APPROVAL_STEP_ROW = {
  id: "823e4567-e89b-12d3-a456-426614174000",
  request_id: "623e4567-e89b-12d3-a456-426614174000",
  step_order: 1,
  approver_type: "specific_user",
  role_id: null,
  specific_user_id: "923e4567-e89b-12d3-a456-426614174000",
  required_approvals: 1,
  approvals_count: 0,
  status: "active",
  created_at: "2026-08-21T00:00:00.000Z",
  updated_at: "2026-08-21T00:00:00.000Z",
};

describe("getLatestAutomationRulePublishApprovalRequest", () => {
  test("returns null (never an error) when no request has ever been opened", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    const request = await getLatestAutomationRulePublishApprovalRequest(client, VERSION_ID);
    assert.equal(request, null);
  });

  test("parses a matched pending request", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_APPROVAL_REQUEST_ROW], error: null });
    const request = await getLatestAutomationRulePublishApprovalRequest(client, VERSION_ID);
    assert.deepEqual(calls[0]?.args, { p_automation_rule_version_id: VERSION_ID });
    assert.equal(request?.status, "pending");
    assert.equal(request?.entityId, VERSION_ID);
  });

  // ISS-2026-237 regression: app.approval_requests.ended_reason is not granted
  // to `authenticated` (20260731210000, Finding 5 CRITICAL) -- app.get_latest_
  // automation_rule_publish_approval_request's own SQL body casts it to null
  // rather than selecting it, so every real RPC row carries `ended_reason: null`
  // explicitly. Prove `endedReason` comes back null, never leaking whatever the
  // column would have held.
  test("never leaks ended_reason -- the RPC row's own null cast comes through as endedReason: null", async () => {
    const { client } = fakeRpcClient({ data: [VALID_APPROVAL_REQUEST_ROW], error: null });
    const request = await getLatestAutomationRulePublishApprovalRequest(client, VERSION_ID);
    assert.equal(request?.status, "pending");
    assert.equal(request?.endedReason, null);
  });
});

describe("listApprovalRequestSteps", () => {
  test("calls list_approval_request_steps and maps step rows in step_order", async () => {
    const { client, calls } = fakeRpcClient({ data: [VALID_APPROVAL_STEP_ROW], error: null });
    const steps = await listApprovalRequestSteps(client, "623e4567-e89b-12d3-a456-426614174000");
    assert.deepEqual(calls[0]?.args, { p_request_id: "623e4567-e89b-12d3-a456-426614174000" });
    assert.equal(steps.length, 1);
    assert.equal(steps[0]?.status, "active");
  });
});
