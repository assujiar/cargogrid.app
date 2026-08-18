import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyBenefitEntitlement,
  parseIssueLoyaltyBenefitEntitlementResult,
  parseLoyaltyBenefitEntitlementEvent,
  parseCustomerPortalLoyaltyBenefitEntitlement,
  formatLoyaltyBenefitValue,
  describeLoyaltyBenefitExpiry,
  IssueLoyaltyBenefitEntitlementInputSchema,
  RedeemLoyaltyBenefitEntitlementInputSchema,
  ReverseLoyaltyBenefitEntitlementInputSchema,
  HoldLoyaltyBenefitEntitlementInputSchema,
  LoyaltyBenefitUpdatedAtCursorSchema,
  LoyaltyBenefitCreatedAtCursorSchema,
} from "./customer-portal-loyalty-benefits.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ENTITLEMENT_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const ENTITLEMENT_ROW = {
  id: ENTITLEMENT_ID,
  tenant_id: TENANT_ID,
  loyalty_account_id: ACCOUNT_ID,
  benefit_type: "cashback",
  value_amount: "50",
  value_cap: "100",
  currency: "USD",
  status: "issued",
  code_hash: null,
  source_type: "manual",
  source_id: null,
  expires_at: null,
  config_version: 1,
  idempotency_key: "issue-1",
  is_fraud_hold: false,
  hold_reason: null,
  held_by: null,
  held_at: null,
  released_by: null,
  released_at: null,
  record_version: 1,
  created_by: "manager1",
  created_at: "2026-08-17T00:00:00.000Z",
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("parseLoyaltyBenefitEntitlement", () => {
  test("maps a full internal cashback entitlement, coercing numeric-string fields", () => {
    const entitlement = parseLoyaltyBenefitEntitlement(ENTITLEMENT_ROW);
    assert.equal(entitlement.valueAmount, 50);
    assert.equal(entitlement.valueCap, 100);
    assert.equal(entitlement.status, "issued");
    assert.equal(entitlement.codeHash, null);
  });

  test("maps a voucher entitlement with a real code_hash", () => {
    const entitlement = parseLoyaltyBenefitEntitlement({ ...ENTITLEMENT_ROW, benefit_type: "voucher", code_hash: "abc123" });
    assert.equal(entitlement.benefitType, "voucher");
    assert.equal(entitlement.codeHash, "abc123");
  });
});

describe("parseIssueLoyaltyBenefitEntitlementResult", () => {
  test("a real first issuance carries a non-null rawCode", () => {
    const result = parseIssueLoyaltyBenefitEntitlementResult({ ...ENTITLEMENT_ROW, benefit_type: "voucher", code_hash: "abc123", raw_code: "CGV-K7M2-QX9B" });
    assert.equal(result.rawCode, "CGV-K7M2-QX9B");
  });

  test("an idempotent replay carries rawCode: null (never recoverable after the first call)", () => {
    const result = parseIssueLoyaltyBenefitEntitlementResult({ ...ENTITLEMENT_ROW, benefit_type: "voucher", code_hash: "abc123", raw_code: null });
    assert.equal(result.rawCode, null);
  });
});

describe("parseLoyaltyBenefitEntitlementEvent", () => {
  test("maps a full internal event, including reason", () => {
    const event = parseLoyaltyBenefitEntitlementEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      entitlement_id: ENTITLEMENT_ID,
      event_type: "held",
      amount: null,
      reason: "Suspected fraud -- internal investigation ref #42",
      actor_auth_user_id: ACTOR_ID,
      actor_label: "manager1",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(event.eventType, "held");
    assert.equal(event.reason, "Suspected fraud -- internal investigation ref #42");
    assert.equal(event.amount, null);
  });
});

describe("customer-facing parser and helpers", () => {
  const CUSTOMER_ROW = {
    id: ENTITLEMENT_ID,
    loyalty_account_id: ACCOUNT_ID,
    program_name: "Cashback Rewards",
    benefit_type: "voucher",
    value_amount: "20",
    value_cap: null,
    currency: "USD",
    status: "issued",
    is_on_hold: false,
    hold_notice: null,
    expires_at: "2026-09-01T00:00:00.000Z",
    record_version: 1,
    created_at: "2026-08-17T00:00:00.000Z",
    updated_at: "2026-08-17T00:00:00.000Z",
  };

  test("parseCustomerPortalLoyaltyBenefitEntitlement never carries an internal-only field even if the row somehow had one", () => {
    const row = parseCustomerPortalLoyaltyBenefitEntitlement({ ...CUSTOMER_ROW, code_hash: "should-never-appear", idempotency_key: "should-never-appear" });
    assert.equal(row.valueAmount, 20);
    assert.equal((row as unknown as Record<string, unknown>).code_hash, undefined);
    assert.equal((row as unknown as Record<string, unknown>).idempotency_key, undefined);
  });

  test("a held entitlement carries a generic hold_notice, never the real internal reason", () => {
    const row = parseCustomerPortalLoyaltyBenefitEntitlement({ ...CUSTOMER_ROW, status: "held", is_on_hold: true, hold_notice: "This benefit is temporarily on hold. Contact your account administrator or support for details." });
    assert.equal(row.isOnHold, true);
    assert.match(row.holdNotice ?? "", /temporarily on hold/);
  });

  test("formatLoyaltyBenefitValue renders currency + 2-decimal amount", () => {
    assert.equal(formatLoyaltyBenefitValue({ valueAmount: 20, currency: "USD" }), "USD 20.00");
  });

  test("describeLoyaltyBenefitExpiry: null when no expiry, a plain-language count when set, Expired when past", () => {
    assert.equal(describeLoyaltyBenefitExpiry({ expiresAt: null }), null);
    assert.equal(describeLoyaltyBenefitExpiry({ expiresAt: new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString() }), "Expired");
    const future = new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString();
    assert.match(describeLoyaltyBenefitExpiry({ expiresAt: future }) ?? "", /Expires in \d+ days?/);
  });
});

describe("input schemas", () => {
  test("IssueLoyaltyBenefitEntitlementInputSchema rejects value_amount exceeding value_cap", () => {
    assert.throws(() =>
      IssueLoyaltyBenefitEntitlementInputSchema.parse({
        tenantId: TENANT_ID,
        loyaltyAccountId: ACCOUNT_ID,
        benefitType: "cashback",
        valueAmount: 100,
        valueCap: 50,
        currency: "USD",
        sourceType: "manual",
        idempotencyKey: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager1",
      }),
    );
  });

  test("IssueLoyaltyBenefitEntitlementInputSchema accepts value_amount exactly at value_cap", () => {
    const parsed = IssueLoyaltyBenefitEntitlementInputSchema.parse({
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      benefitType: "discount",
      valueAmount: 50,
      valueCap: 50,
      currency: "USD",
      sourceType: "manual",
      idempotencyKey: "x",
      actorAuthUserId: ACTOR_ID,
      actorLabel: "manager1",
    });
    assert.equal(parsed.valueAmount, 50);
  });

  test("IssueLoyaltyBenefitEntitlementInputSchema rejects a lowercase/malformed currency", () => {
    assert.throws(() =>
      IssueLoyaltyBenefitEntitlementInputSchema.parse({
        tenantId: TENANT_ID,
        loyaltyAccountId: ACCOUNT_ID,
        benefitType: "cashback",
        valueAmount: 10,
        currency: "usd",
        sourceType: "manual",
        idempotencyKey: "x",
        actorAuthUserId: ACTOR_ID,
        actorLabel: "manager1",
      }),
    );
  });

  test("RedeemLoyaltyBenefitEntitlementInputSchema defaults expectedVersion to null and accepts a bare code string", () => {
    const parsed = RedeemLoyaltyBenefitEntitlementInputSchema.parse({ tenantId: TENANT_ID, entitlementIdOrCode: "CGV-K7M2-QX9B", actorAuthUserId: ACTOR_ID, actorLabel: "customer-alpha" });
    assert.equal(parsed.expectedVersion, null);
    assert.equal(parsed.entitlementIdOrCode, "CGV-K7M2-QX9B");
  });

  test("ReverseLoyaltyBenefitEntitlementInputSchema requires a non-empty reason", () => {
    assert.throws(() => ReverseLoyaltyBenefitEntitlementInputSchema.parse({ tenantId: TENANT_ID, entitlementId: ENTITLEMENT_ID, expectedVersion: 1, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }));
  });

  test("HoldLoyaltyBenefitEntitlementInputSchema requires a non-empty reason", () => {
    assert.throws(() => HoldLoyaltyBenefitEntitlementInputSchema.parse({ tenantId: TENANT_ID, entitlementId: ENTITLEMENT_ID, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }));
  });
});

describe("cursor schemas", () => {
  test("LoyaltyBenefitUpdatedAtCursorSchema requires cursorUpdatedAt when cursorId is present", () => {
    assert.throws(() => LoyaltyBenefitUpdatedAtCursorSchema.parse({ cursorId: ENTITLEMENT_ID }));
    assert.doesNotThrow(() => LoyaltyBenefitUpdatedAtCursorSchema.parse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: ENTITLEMENT_ID }));
  });

  test("LoyaltyBenefitCreatedAtCursorSchema requires cursorCreatedAt when cursorId is present", () => {
    assert.throws(() => LoyaltyBenefitCreatedAtCursorSchema.parse({ cursorId: EVENT_ID }));
  });
});
