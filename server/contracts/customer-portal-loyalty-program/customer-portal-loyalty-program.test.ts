import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyProgram,
  parseLoyaltyProgramRuleVersion,
  parseLoyaltyAccount,
  parseLoyaltyEarningEvent,
  parseCustomerPortalLoyaltyAccount,
  parseCustomerPortalLoyaltyEarningEvent,
  describeLoyaltyEarningBasis,
  LoyaltyUpdatedAtCursorSchema,
  LoyaltyCreatedAtCursorSchema,
  CreateLoyaltyProgramRuleVersionInputSchema,
} from "./customer-portal-loyalty-program.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "223e4567-e89b-12d3-a456-426614174000";
const RULE_VERSION_ID = "323e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "623e4567-e89b-12d3-a456-426614174000";
const AR_OPEN_ITEM_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseLoyaltyProgram", () => {
  test("maps a full program row", () => {
    const program = parseLoyaltyProgram({
      id: PROGRAM_ID,
      tenant_id: TENANT_ID,
      name: "Freight Rewards",
      status: "active",
      description: "Earn points on every paid invoice.",
      created_by: "staff-1",
      record_version: 2,
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T01:00:00.000Z",
    });
    assert.equal(program.status, "active");
    assert.equal(program.recordVersion, 2);
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseLoyaltyProgram({
        id: PROGRAM_ID,
        tenant_id: TENANT_ID,
        name: "Freight Rewards",
        status: "archived",
        description: null,
        created_by: null,
        record_version: 1,
        created_at: "2026-08-17T00:00:00.000Z",
        updated_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyProgramRuleVersion", () => {
  test("maps a published version, coercing string rate to number", () => {
    const version = parseLoyaltyProgramRuleVersion({
      id: RULE_VERSION_ID,
      tenant_id: TENANT_ID,
      program_id: PROGRAM_ID,
      version_number: 1,
      earning_basis: "per_paid_invoice_amount",
      reward_type: "points",
      rate: "0.100000",
      eligibility_config: { min_invoice_amount: 50 },
      status: "published",
      effective_from: "2026-08-01T00:00:00.000Z",
      effective_to: null,
      published_by: "staff-1",
      published_at: "2026-08-01T00:00:00.000Z",
      record_version: 1,
      created_by: "staff-1",
      created_at: "2026-07-30T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(version.rate, 0.1);
    assert.equal(version.status, "published");
    assert.deepEqual(version.eligibilityConfig, { min_invoice_amount: 50 });
  });

  test("maps a draft version with all publish fields null", () => {
    const version = parseLoyaltyProgramRuleVersion({
      id: RULE_VERSION_ID,
      tenant_id: TENANT_ID,
      program_id: PROGRAM_ID,
      version_number: 2,
      earning_basis: "per_paid_invoice_amount",
      reward_type: "cashback",
      rate: 0.02,
      eligibility_config: {},
      status: "draft",
      effective_from: null,
      effective_to: null,
      published_by: null,
      published_at: null,
      record_version: 1,
      created_by: "staff-1",
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(version.status, "draft");
    assert.equal(version.publishedBy, null);
  });
});

describe("parseLoyaltyAccount", () => {
  test("maps an active enrollment", () => {
    const account = parseLoyaltyAccount({
      id: ACCOUNT_ID,
      tenant_id: TENANT_ID,
      customer_account_id: CUSTOMER_ACCOUNT_ID,
      program_id: PROGRAM_ID,
      status: "active",
      enrolled_at: "2026-08-01T00:00:00.000Z",
      closed_by: null,
      closed_at: null,
      closed_reason: null,
      record_version: 1,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(account.status, "active");
    assert.equal(account.closedAt, null);
  });
});

describe("parseLoyaltyEarningEvent", () => {
  test("maps an original earning event", () => {
    const event = parseLoyaltyEarningEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      program_id: PROGRAM_ID,
      rule_version_id: RULE_VERSION_ID,
      reward_type: "points",
      amount: "110",
      source_type: "finance_invoice_paid",
      source_id: AR_OPEN_ITEM_ID,
      idempotency_key: `ar-open-item:${AR_OPEN_ITEM_ID}`,
      corrects_event_id: null,
      reason: null,
      created_by: "staff-1",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(event.amount, 110);
    assert.equal(event.correctsEventId, null);
  });

  test("maps a reversal event, amount negative and corrects_event_id set", () => {
    const event = parseLoyaltyEarningEvent({
      id: "823e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      program_id: PROGRAM_ID,
      rule_version_id: RULE_VERSION_ID,
      reward_type: "points",
      amount: -110,
      source_type: "reversal",
      source_id: EVENT_ID,
      idempotency_key: `reversal:${EVENT_ID}`,
      corrects_event_id: EVENT_ID,
      reason: "duplicate payment reversed",
      created_by: "staff-1",
      created_at: "2026-08-17T02:00:00.000Z",
    });
    assert.equal(event.amount, -110);
    assert.equal(event.correctsEventId, EVENT_ID);
    assert.equal(event.sourceType, "reversal");
  });
});

describe("customer-facing projections", () => {
  test("parseCustomerPortalLoyaltyAccount maps a program-joined row", () => {
    const account = parseCustomerPortalLoyaltyAccount({
      id: ACCOUNT_ID,
      customer_account_id: CUSTOMER_ACCOUNT_ID,
      program_id: PROGRAM_ID,
      program_name: "Freight Rewards",
      status: "active",
      enrolled_at: "2026-08-01T00:00:00.000Z",
      record_version: 1,
      updated_at: "2026-08-01T00:00:00.000Z",
    });
    assert.equal(account.programName, "Freight Rewards");
  });

  test("parseCustomerPortalLoyaltyEarningEvent never carries internal linkage fields", () => {
    const event = parseCustomerPortalLoyaltyEarningEvent({
      id: EVENT_ID,
      program_name: "Freight Rewards",
      reward_type: "points",
      amount: "110",
      earning_basis: "per_paid_invoice_amount",
      rate: "0.1",
      source_type: "finance_invoice_paid",
      reason: null,
      corrects_event_id: null,
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(event.amount, 110);
    assert.equal(event.rate, 0.1);
    assert.ok(!("loyaltyAccountId" in event));
    assert.ok(!("ruleVersionId" in event));
  });
});

describe("describeLoyaltyEarningBasis", () => {
  test("renders a customer-safe, plain-language sentence for per_paid_invoice_amount", () => {
    const text = describeLoyaltyEarningBasis("per_paid_invoice_amount", "points", 0.1);
    assert.match(text, /10\.00%/);
    assert.match(text, /points/);
  });

  test("falls back to a generic rendering for an unrecognized basis, never throwing", () => {
    const text = describeLoyaltyEarningBasis("tier_multiplier_bonus", "cashback", 0.05);
    assert.match(text, /tier_multiplier_bonus/);
    assert.match(text, /cashback/);
  });
});

describe("cursor schemas", () => {
  test("LoyaltyUpdatedAtCursorSchema rejects a half-supplied cursor", () => {
    const result = LoyaltyUpdatedAtCursorSchema.safeParse({ cursorId: PROGRAM_ID });
    assert.equal(result.success, false);
  });

  test("LoyaltyCreatedAtCursorSchema accepts a fully-supplied cursor", () => {
    const result = LoyaltyCreatedAtCursorSchema.safeParse({ cursorCreatedAt: "2026-08-17T00:00:00.000Z", cursorId: EVENT_ID });
    assert.equal(result.success, true);
  });
});

describe("CreateLoyaltyProgramRuleVersionInputSchema", () => {
  test("rejects a non-positive rate", () => {
    const result = CreateLoyaltyProgramRuleVersionInputSchema.safeParse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      earningBasis: "per_paid_invoice_amount",
      rewardType: "points",
      rate: 0,
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.equal(result.success, false);
  });

  test("defaults eligibilityConfig to an empty object", () => {
    const result = CreateLoyaltyProgramRuleVersionInputSchema.parse({
      tenantId: TENANT_ID,
      programId: PROGRAM_ID,
      earningBasis: "per_paid_invoice_amount",
      rewardType: "points",
      rate: 0.1,
      actorAuthUserId: TENANT_ID,
      actorLabel: "staff-1",
    });
    assert.deepEqual(result.eligibilityConfig, {});
  });
});
