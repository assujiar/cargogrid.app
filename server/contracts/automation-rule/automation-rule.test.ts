import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseAutomationRule,
  parseAutomationRuleVersion,
  parseAutomationRuleExecution,
  parseDryRunAutomationRuleResult,
  AutomationConditionsSchema,
  AutomationActionsSchema,
} from "./automation-rule.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const VERSION_ID = "423e4567-e89b-12d3-a456-426614174000";

describe("parseAutomationRule", () => {
  test("maps snake_case columns to camelCase", () => {
    const rule = parseAutomationRule({
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
    });
    assert.equal(rule.tenantId, TENANT_ID);
    assert.equal(rule.currentVersionId, null);
    assert.equal(rule.cooldownSeconds, 60);
  });
});

describe("parseAutomationRuleVersion", () => {
  test("defaults conditions/actions to empty arrays when absent", () => {
    const version = parseAutomationRuleVersion({
      id: VERSION_ID,
      automation_rule_id: RULE_ID,
      version_number: 1,
      status: "draft",
      trigger_event_type: null,
      conditions: null,
      actions: null,
      created_at: "2026-08-21T00:00:00.000Z",
      published_at: null,
    });
    assert.deepEqual(version.conditions, []);
    assert.deepEqual(version.actions, []);
  });

  test("parses a real trigger/conditions/actions shape", () => {
    const version = parseAutomationRuleVersion({
      id: VERSION_ID,
      automation_rule_id: RULE_ID,
      version_number: 2,
      status: "published",
      trigger_event_type: "ticket.created",
      conditions: [{ field: "priority", operator: "eq", value: "high" }],
      actions: [{ action_type: "notify", notification_type_code: "x", channel: "in_app", recipient_field: "recipient_auth_user_id" }],
      created_at: "2026-08-21T00:00:00.000Z",
      published_at: "2026-08-21T00:05:00.000Z",
    });
    assert.equal(version.triggerEventType, "ticket.created");
    assert.equal(version.conditions[0]?.operator, "eq");
    assert.equal(version.actions[0]?.action_type, "notify");
  });
});

describe("parseAutomationRuleExecution", () => {
  test("parses a suppressed execution row", () => {
    const execution = parseAutomationRuleExecution({
      id: "523e4567-e89b-12d3-a456-426614174000",
      automation_rule_id: RULE_ID,
      automation_rule_version_id: VERSION_ID,
      trigger_event_type: "ticket.created",
      source_event_id: null,
      event_payload: { priority: "high" },
      status: "suppressed",
      suppressed_reason: "cooldown",
      actions_taken: [],
      executed_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(execution.status, "suppressed");
    assert.equal(execution.suppressedReason, "cooldown");
  });
});

describe("parseDryRunAutomationRuleResult", () => {
  test("parses a matching dry run", () => {
    const result = parseDryRunAutomationRuleResult({
      matched: true,
      trigger_event_type: "ticket.created",
      would_fire_actions: [{ action_type: "enqueue_job", job_type: "automation_action_execution" }],
      valid: true,
      validation_error: null,
    });
    assert.equal(result.matched, true);
    assert.equal(result.wouldFireActions.length, 1);
    assert.equal(result.valid, true);
    assert.equal(result.validationError, null);
  });

  // Batch 2 Tier C fix (20260803030000_harden_intelligence_batch2_tier_c_review_fixes.sql,
  // finding 6): app.dry_run_automation_rule now reports valid=false with a real
  // validation_error for a draft carrying a governance-rejected action_type, instead of
  // silently reporting it as something that "would fire".
  test("surfaces valid=false and a real validationError for a governance-rejected draft", () => {
    // wouldFireActions itself stays within AutomationActionsSchema's own allowlist here
    // (the RPC's own actions column shares that same allowlist for a STORED draft, since
    // app.set_automation_rule_definition only ever runs structural, not business-rule,
    // validation on write) -- this test proves the valid/validationError plumbing itself,
    // the live business-rule-rejection case is proven end to end against a real disposable
    // database in scripts/db-tests/automation-rule-engine.sql's own Tier C regression.
    const result = parseDryRunAutomationRuleResult({
      matched: true,
      trigger_event_type: "probe.event",
      would_fire_actions: [{ action_type: "enqueue_job", job_type: "automation_action_execution" }],
      valid: false,
      validation_error: "automation_rule_invalid_action_type: delete_customer_ledger_entry is not a supported action_type",
    });
    assert.equal(result.valid, false);
    assert.match(result.validationError ?? "", /automation_rule_invalid_action_type/);
  });

  test("defaults valid=true/validationError=null when the RPC response predates this fix", () => {
    const result = parseDryRunAutomationRuleResult({
      matched: false,
      trigger_event_type: "ticket.created",
      would_fire_actions: [],
    });
    assert.equal(result.valid, true);
    assert.equal(result.validationError, null);
  });
});

describe("AutomationConditionsSchema", () => {
  test("accepts a valid condition array", () => {
    const parsed = AutomationConditionsSchema.parse([{ field: "priority", operator: "eq", value: "high" }]);
    assert.equal(parsed.length, 1);
  });

  test("rejects an unsupported operator", () => {
    assert.throws(() => AutomationConditionsSchema.parse([{ field: "priority", operator: "matches", value: "high" }]));
  });
});

describe("AutomationActionsSchema", () => {
  test("accepts a valid action array", () => {
    const parsed = AutomationActionsSchema.parse([{ action_type: "notify", notification_type_code: "x", channel: "in_app", recipient_field: "recipient_auth_user_id" }]);
    assert.equal(parsed.length, 1);
  });

  test("rejects an unsupported action_type", () => {
    assert.throws(() => AutomationActionsSchema.parse([{ action_type: "delete_everything" }]));
  });
});
