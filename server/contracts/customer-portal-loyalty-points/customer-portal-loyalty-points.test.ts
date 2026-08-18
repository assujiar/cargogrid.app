import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyPointLot,
  parseLoyaltyPointLedgerEntry,
  parseLoyaltyPointBalance,
  parseLoyaltyPointAdjustmentRequest,
  parseCustomerPortalLoyaltyPointBalance,
  parseCustomerPortalLoyaltyPointLedgerEntry,
  parseCustomerPortalLoyaltyPointExpiryScheduleEntry,
  describeLoyaltyPointExpiry,
  PostLoyaltyPointsEarnedInputSchema,
  RequestLoyaltyPointAdjustmentInputSchema,
  DecideLoyaltyPointAdjustmentInputSchema,
  LoyaltyPointUpdatedAtCursorSchema,
  LoyaltyPointCreatedAtCursorSchema,
  LoyaltyPointExpiresAtCursorSchema,
} from "./customer-portal-loyalty-points.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const LOT_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENTRY_ID = "423e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const REQUEST_ID = "623e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ACCOUNT_ID = "723e4567-e89b-12d3-a456-426614174000";
const PROGRAM_ID = "823e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "923e4567-e89b-12d3-a456-426614174000";

describe("parseLoyaltyPointLot", () => {
  test("maps an active lot, coercing numeric-string fields", () => {
    const lot = parseLoyaltyPointLot({
      id: LOT_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      source_earning_event_id: EVENT_ID,
      original_amount: "100",
      remaining_amount: "40",
      expires_at: "2026-09-01T00:00:00.000Z",
      status: "active",
      record_version: 1,
      created_at: "2026-08-01T00:00:00.000Z",
      updated_at: "2026-08-10T00:00:00.000Z",
    });
    assert.equal(lot.originalAmount, 100);
    assert.equal(lot.remainingAmount, 40);
    assert.equal(lot.status, "active");
  });
});

describe("parseLoyaltyPointLedgerEntry", () => {
  test("maps a full internal (staff-facing) entry, including reason", () => {
    const entry = parseLoyaltyPointLedgerEntry({
      id: ENTRY_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      event_type: "adjustment",
      amount: "50",
      lot_id: null,
      source_type: "manual_adjustment",
      source_id: REQUEST_ID,
      idempotency_key: "adjustment:" + REQUEST_ID,
      corrects_entry_id: null,
      reason: "Suspected duplicate award -- internal fraud investigation ref #4521",
      config_version: 1,
      created_by: "manager1",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(entry.amount, 50);
    assert.equal(entry.reason, "Suspected duplicate award -- internal fraud investigation ref #4521");
    assert.equal(entry.lotId, null);
  });
});

describe("parseLoyaltyPointBalance", () => {
  test("maps earned/consumed/available", () => {
    const balance = parseLoyaltyPointBalance({
      id: LOT_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      total_earned: "390",
      total_consumed: "150",
      available: "240",
      record_version: 3,
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(balance.totalEarned, 390);
    assert.equal(balance.totalConsumed, 150);
    assert.equal(balance.available, 240);
  });
});

describe("parseLoyaltyPointAdjustmentRequest", () => {
  test("maps a pending request with decision fields null", () => {
    const request = parseLoyaltyPointAdjustmentRequest({
      id: REQUEST_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      adjustment_amount: "50",
      reason: "internal note",
      requested_by_auth_user_id: ACTOR_ID,
      requested_by: "manager1",
      requested_at: "2026-08-17T00:00:00.000Z",
      status: "pending_approval",
      decided_by_auth_user_id: null,
      decided_by: null,
      decided_at: null,
      decision_notes: null,
      ledger_entry_id: null,
      idempotency_key: "adj-req-1",
      record_version: 1,
      created_by: "manager1",
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(request.status, "pending_approval");
    assert.equal(request.decidedByAuthUserId, null);
    assert.equal(request.ledgerEntryId, null);
  });
});

describe("customer-facing parsers", () => {
  test("parseCustomerPortalLoyaltyPointBalance maps a customer-safe balance row", () => {
    const balance = parseCustomerPortalLoyaltyPointBalance({
      loyalty_account_id: ACCOUNT_ID,
      customer_account_id: CUSTOMER_ACCOUNT_ID,
      program_id: PROGRAM_ID,
      program_name: "Points Rewards",
      total_earned: "390",
      total_consumed: "0",
      available: "390",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(balance.available, 390);
    assert.equal(balance.programName, "Points Rewards");
  });

  test("parseCustomerPortalLoyaltyPointLedgerEntry never carries a reason field, even if the row somehow had one", () => {
    const entry = parseCustomerPortalLoyaltyPointLedgerEntry({
      id: ENTRY_ID,
      program_name: "Points Rewards",
      event_type: "adjustment",
      amount: "50",
      description: "Account adjustment",
      created_at: "2026-08-17T00:00:00.000Z",
      // A raw row that ALSO happened to carry a `reason` key (e.g. from a
      // careless SELECT *) must not surface it -- the parser's own explicit
      // field list is the structural guarantee, not the schema's `strict()`.
      reason: "Suspected duplicate award -- internal fraud investigation ref #4521",
    });
    assert.equal(entry.description, "Account adjustment");
    assert.equal((entry as Record<string, unknown>).reason, undefined);
  });

  test("parseCustomerPortalLoyaltyPointExpiryScheduleEntry maps a schedule row", () => {
    const row = parseCustomerPortalLoyaltyPointExpiryScheduleEntry({
      id: LOT_ID,
      program_name: "Points Rewards",
      remaining_amount: "30",
      expires_at: "2026-09-01T00:00:00.000Z",
    });
    assert.equal(row.remainingAmount, 30);
  });
});

describe("describeLoyaltyPointExpiry", () => {
  test("renders a plain-language, customer-safe expiry description", () => {
    const future = new Date(Date.now() + 5 * 24 * 60 * 60 * 1000).toISOString();
    const description = describeLoyaltyPointExpiry({ id: LOT_ID, programName: "Points Rewards", remainingAmount: 30, expiresAt: future });
    assert.match(description, /30 points from Points Rewards expire in \d+ days?\./);
  });
});

describe("input schemas", () => {
  test("PostLoyaltyPointsEarnedInputSchema defaults expiryDays to 365 and rejects an out-of-range value", () => {
    const parsed = PostLoyaltyPointsEarnedInputSchema.parse({ tenantId: TENANT_ID, earningEventId: EVENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1" });
    assert.equal(parsed.expiryDays, 365);
    assert.throws(() => PostLoyaltyPointsEarnedInputSchema.parse({ tenantId: TENANT_ID, earningEventId: EVENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1", expiryDays: 0 }));
    assert.throws(() => PostLoyaltyPointsEarnedInputSchema.parse({ tenantId: TENANT_ID, earningEventId: EVENT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "manager1", expiryDays: 3651 }));
  });

  test("RequestLoyaltyPointAdjustmentInputSchema rejects a zero amount and a blank reason", () => {
    assert.throws(() => RequestLoyaltyPointAdjustmentInputSchema.parse({ tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, adjustmentAmount: 0, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }));
    assert.throws(() => RequestLoyaltyPointAdjustmentInputSchema.parse({ tenantId: TENANT_ID, loyaltyAccountId: ACCOUNT_ID, adjustmentAmount: 10, reason: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }));
  });

  test("DecideLoyaltyPointAdjustmentInputSchema requires a non-empty decisionNotes and a valid decision", () => {
    assert.throws(() =>
      DecideLoyaltyPointAdjustmentInputSchema.parse({ tenantId: TENANT_ID, adjustmentId: REQUEST_ID, expectedVersion: 1, decision: "approved", decisionNotes: "", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
    );
    assert.throws(() =>
      DecideLoyaltyPointAdjustmentInputSchema.parse({ tenantId: TENANT_ID, adjustmentId: REQUEST_ID, expectedVersion: 1, decision: "maybe", decisionNotes: "x", actorAuthUserId: ACTOR_ID, actorLabel: "manager1" }),
    );
  });
});

describe("cursor schemas", () => {
  test("LoyaltyPointUpdatedAtCursorSchema requires cursorUpdatedAt when cursorId is present", () => {
    assert.throws(() => LoyaltyPointUpdatedAtCursorSchema.parse({ cursorId: LOT_ID }));
    assert.doesNotThrow(() => LoyaltyPointUpdatedAtCursorSchema.parse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: LOT_ID }));
  });

  test("LoyaltyPointCreatedAtCursorSchema requires cursorCreatedAt when cursorId is present", () => {
    assert.throws(() => LoyaltyPointCreatedAtCursorSchema.parse({ cursorId: ENTRY_ID }));
  });

  test("LoyaltyPointExpiresAtCursorSchema requires cursorExpiresAt when cursorId is present", () => {
    assert.throws(() => LoyaltyPointExpiresAtCursorSchema.parse({ cursorId: LOT_ID }));
    assert.doesNotThrow(() => LoyaltyPointExpiresAtCursorSchema.parse({ cursorExpiresAt: "2026-09-01T00:00:00.000Z", cursorId: LOT_ID }));
  });
});
