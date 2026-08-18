import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseLoyaltyRedemption,
  parseLoyaltyRedemptionEvent,
  parseCustomerPortalLoyaltyRedemption,
  describeLoyaltyRedemptionStatus,
  canCancelLoyaltyRedemption,
  LoyaltyRedemptionUpdatedAtCursorSchema,
  DecideLoyaltyRedemptionInputSchema,
  SubmitLoyaltyRedemptionInputSchema,
} from "./customer-portal-loyalty-redemptions.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "223e4567-e89b-12d3-a456-426614174000";
const REWARD_ID = "323e4567-e89b-12d3-a456-426614174000";
const REDEMPTION_ID = "423e4567-e89b-12d3-a456-426614174000";
const ENTITLEMENT_ID = "523e4567-e89b-12d3-a456-426614174000";
const RESERVATION_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseLoyaltyRedemption", () => {
  test("maps a pending_approval physical_item redemption, unreserved", () => {
    const redemption = parseLoyaltyRedemption({
      id: REDEMPTION_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      reward_id: REWARD_ID,
      reward_version_number: 1,
      reward_name: "Physical Reward",
      reward_type: "physical_item",
      points_consumed: "50",
      stock_reservation_id: null,
      benefit_entitlement_id: null,
      status: "pending_approval",
      fulfillment_status: "pending",
      decision_reason: null,
      decided_by: null,
      decided_at: null,
      idempotency_key: "idem-1",
      record_version: 1,
      created_by: "customer-1",
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(redemption.status, "pending_approval");
    assert.equal(redemption.pointsConsumed, 50);
    assert.equal(redemption.stockReservationId, null);
  });

  test("maps a fulfilled discount_voucher redemption with a real entitlement/reservation reference", () => {
    const redemption = parseLoyaltyRedemption({
      id: REDEMPTION_ID,
      tenant_id: TENANT_ID,
      loyalty_account_id: ACCOUNT_ID,
      reward_id: REWARD_ID,
      reward_version_number: 2,
      reward_name: "Voucher Reward",
      reward_type: "discount_voucher",
      points_consumed: "100",
      stock_reservation_id: RESERVATION_ID,
      benefit_entitlement_id: ENTITLEMENT_ID,
      status: "fulfilled",
      fulfillment_status: "not_applicable",
      decision_reason: "auto-approved: eligibility, stock, and points re-validated at decision time",
      decided_by: "manager1",
      decided_at: "2026-08-17T00:05:00.000Z",
      idempotency_key: "idem-2",
      record_version: 2,
      created_by: "manager1",
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T00:05:00.000Z",
    });
    assert.equal(redemption.status, "fulfilled");
    assert.equal(redemption.benefitEntitlementId, ENTITLEMENT_ID);
    assert.equal(redemption.fulfillmentStatus, "not_applicable");
  });

  test("rejects an unrecognized status", () => {
    assert.throws(() =>
      parseLoyaltyRedemption({
        id: REDEMPTION_ID,
        tenant_id: TENANT_ID,
        loyalty_account_id: ACCOUNT_ID,
        reward_id: REWARD_ID,
        reward_version_number: 1,
        reward_name: "x",
        reward_type: "physical_item",
        points_consumed: "0",
        stock_reservation_id: null,
        benefit_entitlement_id: null,
        status: "made_up_status",
        fulfillment_status: "pending",
        decision_reason: null,
        decided_by: null,
        decided_at: null,
        idempotency_key: "idem-3",
        record_version: 1,
        created_by: null,
        created_at: "2026-08-17T00:00:00.000Z",
        updated_at: "2026-08-17T00:00:00.000Z",
      }),
    );
  });
});

describe("parseLoyaltyRedemptionEvent", () => {
  test("maps a rejected event with a real reason", () => {
    const event = parseLoyaltyRedemptionEvent({
      id: REDEMPTION_ID,
      tenant_id: TENANT_ID,
      redemption_id: REDEMPTION_ID,
      event_type: "rejected",
      reason: "declined by staff",
      actor_auth_user_id: ACCOUNT_ID,
      actor_label: "manager1",
      created_at: "2026-08-17T00:00:00.000Z",
    });
    assert.equal(event.eventType, "rejected");
    assert.equal(event.reason, "declined by staff");
  });
});

describe("customer-facing redemption projection", () => {
  test("parseCustomerPortalLoyaltyRedemption maps a fulfilling row", () => {
    const redemption = parseCustomerPortalLoyaltyRedemption({
      redemption_id: REDEMPTION_ID,
      loyalty_account_id: ACCOUNT_ID,
      reward_id: REWARD_ID,
      reward_name: "Physical Reward",
      reward_type: "physical_item",
      points_consumed: "50",
      benefit_entitlement_id: null,
      status: "fulfilling",
      fulfillment_status: "in_fulfillment",
      decision_reason: "looks good",
      decided_at: "2026-08-17T00:05:00.000Z",
      record_version: 2,
      created_at: "2026-08-17T00:00:00.000Z",
      updated_at: "2026-08-17T00:05:00.000Z",
    });
    assert.equal(redemption.status, "fulfilling");
    assert.ok(!("idempotency_key" in redemption));
    assert.ok(!("idempotencyKey" in redemption));
    assert.ok(!("stock_reservation_id" in redemption));
    assert.ok(!("stockReservationId" in redemption));
  });
});

describe("describeLoyaltyRedemptionStatus", () => {
  test("renders a customer-safe label for pending_approval", () => {
    assert.equal(describeLoyaltyRedemptionStatus({ status: "pending_approval", fulfillmentStatus: "pending" }), "Awaiting review");
  });

  test("renders distinct labels for fulfilling depending on fulfillment_status", () => {
    assert.equal(describeLoyaltyRedemptionStatus({ status: "fulfilling", fulfillmentStatus: "in_fulfillment" }), "Being prepared");
    assert.equal(describeLoyaltyRedemptionStatus({ status: "fulfilling", fulfillmentStatus: "pending" }), "Approved, preparing to fulfill");
  });

  test("renders a customer-safe label for rejected -- never the raw enum value", () => {
    const text = describeLoyaltyRedemptionStatus({ status: "rejected", fulfillmentStatus: "not_applicable" });
    assert.equal(text, "Not approved");
    assert.notEqual(text, "rejected");
  });
});

describe("canCancelLoyaltyRedemption", () => {
  test("only pending_approval is cancellable", () => {
    assert.equal(canCancelLoyaltyRedemption({ status: "pending_approval" }), true);
    assert.equal(canCancelLoyaltyRedemption({ status: "fulfilling" }), false);
    assert.equal(canCancelLoyaltyRedemption({ status: "fulfilled" }), false);
    assert.equal(canCancelLoyaltyRedemption({ status: "cancelled" }), false);
  });
});

describe("cursor schema", () => {
  test("LoyaltyRedemptionUpdatedAtCursorSchema rejects a half-supplied cursor", () => {
    const result = LoyaltyRedemptionUpdatedAtCursorSchema.safeParse({ cursorId: REDEMPTION_ID });
    assert.equal(result.success, false);
  });

  test("LoyaltyRedemptionUpdatedAtCursorSchema accepts a fully-supplied cursor", () => {
    const result = LoyaltyRedemptionUpdatedAtCursorSchema.safeParse({ cursorUpdatedAt: "2026-08-17T00:00:00.000Z", cursorId: REDEMPTION_ID });
    assert.equal(result.success, true);
  });
});

describe("SubmitLoyaltyRedemptionInputSchema", () => {
  test("rejects an empty idempotency key", () => {
    const result = SubmitLoyaltyRedemptionInputSchema.safeParse({
      tenantId: TENANT_ID,
      loyaltyAccountId: ACCOUNT_ID,
      rewardId: REWARD_ID,
      idempotencyKey: "",
      actorAuthUserId: TENANT_ID,
      actorLabel: "customer-1",
    });
    assert.equal(result.success, false);
  });
});

describe("DecideLoyaltyRedemptionInputSchema", () => {
  test("rejects a reject decision with no reason", () => {
    const result = DecideLoyaltyRedemptionInputSchema.safeParse({
      tenantId: TENANT_ID,
      redemptionId: REDEMPTION_ID,
      expectedVersion: 1,
      decision: "reject",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, false);
  });

  test("accepts an approve decision with no reason", () => {
    const result = DecideLoyaltyRedemptionInputSchema.safeParse({
      tenantId: TENANT_ID,
      redemptionId: REDEMPTION_ID,
      expectedVersion: 1,
      decision: "approve",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, true);
  });

  test("accepts a reject decision with a real reason", () => {
    const result = DecideLoyaltyRedemptionInputSchema.safeParse({
      tenantId: TENANT_ID,
      redemptionId: REDEMPTION_ID,
      expectedVersion: 1,
      decision: "reject",
      decisionReason: "out of stock at this location",
      actorAuthUserId: TENANT_ID,
      actorLabel: "manager1",
    });
    assert.equal(result.success, true);
  });
});
