import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseQuotationApprovalRuleVersion,
  parseQuotationApprovalRequirement,
  CreateQuotationApprovalRuleVersionInputSchema,
  PublishQuotationApprovalRuleVersionInputSchema,
  DecideQuotationApprovalStepInputSchema,
} from "./quotation-approval.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const STEP_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseQuotationApprovalRuleVersion", () => {
  test("maps a margin-only rule, leaving discount/value null", () => {
    const rule = parseQuotationApprovalRuleVersion({
      id: RULE_ID,
      tenant_id: TENANT_ID,
      min_margin_pct: 40,
      max_discount_pct: null,
      min_value_amount: null,
      status: "published",
      supersedes_version_id: null,
      record_version: 2,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
      updated_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(rule.minMarginPct, 40);
    assert.equal(rule.maxDiscountPct, null);
    assert.equal(rule.status, "published");
  });
});

describe("parseQuotationApprovalRequirement", () => {
  test("maps a required=true row with reason codes", () => {
    const requirement = parseQuotationApprovalRequirement({ required: true, reasons: ["below_minimum_margin"], rule_version_id: RULE_ID });
    assert.equal(requirement.required, true);
    assert.deepEqual(requirement.reasons, ["below_minimum_margin"]);
    assert.equal(requirement.ruleVersionId, RULE_ID);
  });

  test("maps a required=false row with no published rule (ruleVersionId null)", () => {
    const requirement = parseQuotationApprovalRequirement({ required: false, reasons: [], rule_version_id: null });
    assert.equal(requirement.required, false);
    assert.equal(requirement.ruleVersionId, null);
  });
});

describe("CreateQuotationApprovalRuleVersionInputSchema", () => {
  test("accepts a margin-only threshold", () => {
    const parsed = CreateQuotationApprovalRuleVersionInputSchema.parse({
      tenantId: TENANT_ID,
      minMarginPct: 40,
      actorAuthUserId: ACTOR_ID,
      createdBy: "tester",
    });
    assert.equal(parsed.minMarginPct, 40);
    assert.equal(parsed.maxDiscountPct, null);
  });

  test("rejects a rule with every threshold null", () => {
    assert.throws(() =>
      CreateQuotationApprovalRuleVersionInputSchema.parse({
        tenantId: TENANT_ID,
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });

  test("rejects a margin percentage above 100", () => {
    assert.throws(() =>
      CreateQuotationApprovalRuleVersionInputSchema.parse({
        tenantId: TENANT_ID,
        minMarginPct: 150,
        actorAuthUserId: ACTOR_ID,
        createdBy: "tester",
      }),
    );
  });
});

describe("PublishQuotationApprovalRuleVersionInputSchema", () => {
  test("defaults supersedesVersionId to null", () => {
    const parsed = PublishQuotationApprovalRuleVersionInputSchema.parse({
      ruleVersionId: RULE_ID,
      expectedVersion: 1,
      actorAuthUserId: ACTOR_ID,
      actorLabel: "tester",
    });
    assert.equal(parsed.supersedesVersionId, null);
  });
});

describe("DecideQuotationApprovalStepInputSchema", () => {
  test("accepts an approve decision with no reason", () => {
    const parsed = DecideQuotationApprovalStepInputSchema.parse({
      requestStepId: STEP_ID,
      decision: "approved",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager",
    });
    assert.equal(parsed.decision, "approved");
    assert.equal(parsed.reason, null);
  });

  test("rejects a decision value outside approved/rejected", () => {
    assert.throws(() =>
      DecideQuotationApprovalStepInputSchema.parse({
        requestStepId: STEP_ID,
        decision: "revise",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager",
      }),
    );
  });
});
