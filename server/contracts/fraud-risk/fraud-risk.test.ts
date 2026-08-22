import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseRiskSignal, parseRiskSignalReview, parseRiskSignalAction, RequestRiskSignalInputSchema, HoldRiskSignalEntityInputSchema, DecideRiskSignalInputSchema } from "./fraud-risk.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const SIGNAL_ID = "323e4567-e89b-12d3-a456-426614174000";
const ENTITY_ID = "423e4567-e89b-12d3-a456-426614174000";
const REVIEW_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTION_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseRiskSignal", () => {
  test("round-trips a succeeded row", () => {
    const signal = parseRiskSignal({
      id: SIGNAL_ID, tenant_id: TENANT_ID, risk_domain: "loyalty", entity_type: "loyalty_account", entity_id: ENTITY_ID,
      input_snapshot: { redemption_count_24h: 12 }, ai_governed_request_id: null, status: "succeeded", score: "82",
      band: "high", requested_by: "rep", created_at: "2026-08-22T00:00:00.000Z", completed_at: "2026-08-22T00:01:00.000Z",
    });
    assert.equal(signal.band, "high");
    assert.equal(signal.score, 82);
  });

  test("rejects an unrecognized band", () => {
    assert.throws(() =>
      parseRiskSignal({
        id: SIGNAL_ID, tenant_id: TENANT_ID, risk_domain: "loyalty", entity_type: "loyalty_account", entity_id: ENTITY_ID,
        input_snapshot: {}, ai_governed_request_id: null, status: "succeeded", score: null, band: "not-a-real-band",
        requested_by: null, created_at: "2026-08-22T00:00:00.000Z", completed_at: null,
      }),
    );
  });
});

describe("parseRiskSignalReview", () => {
  test("round-trips a confirmed review", () => {
    const review = parseRiskSignalReview({
      id: REVIEW_ID, tenant_id: TENANT_ID, risk_signal_id: SIGNAL_ID, decision: "confirmed",
      reviewer_note: "clear pattern", decided_by: "rep", decided_at: "2026-08-22T00:00:00.000Z",
    });
    assert.equal(review.decision, "confirmed");
  });
});

describe("parseRiskSignalAction", () => {
  test("round-trips an active hold", () => {
    const action = parseRiskSignalAction({
      id: ACTION_ID, tenant_id: TENANT_ID, risk_signal_id: SIGNAL_ID, reason: "internal reason",
      customer_safe_reason: "we are reviewing your account", status: "active", held_by: "rep",
      held_at: "2026-08-22T00:00:00.000Z", released_by: null, released_at: null, release_reason: null,
    });
    assert.equal(action.status, "active");
    assert.notEqual(action.reason, action.customerSafeReason);
  });
});

describe("RequestRiskSignalInputSchema", () => {
  test("rejects an unrecognized risk domain", () => {
    assert.throws(() =>
      RequestRiskSignalInputSchema.parse({
        tenantId: TENANT_ID, riskDomain: "not-a-real-domain", entityType: "loyalty_account", entityId: ENTITY_ID,
        inputSnapshot: {}, idempotencyKey: "idem-1", actorAuthUserId: ACTOR_ID, actorLabel: "rep",
      }),
    );
  });
});

describe("HoldRiskSignalEntityInputSchema", () => {
  test("rejects an empty customer-safe reason", () => {
    assert.throws(() =>
      HoldRiskSignalEntityInputSchema.parse({ signalId: SIGNAL_ID, tenantId: TENANT_ID, reason: "internal", customerSafeReason: "", actorAuthUserId: ACTOR_ID, actorLabel: "rep" }),
    );
  });
});

describe("DecideRiskSignalInputSchema", () => {
  test("defaults reviewerNote to null", () => {
    const parsed = DecideRiskSignalInputSchema.parse({ signalId: SIGNAL_ID, tenantId: TENANT_ID, decision: "dismissed", actorAuthUserId: ACTOR_ID, actorLabel: "rep" });
    assert.equal(parsed.reviewerNote, null);
  });
});
