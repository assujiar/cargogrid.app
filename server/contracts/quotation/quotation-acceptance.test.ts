import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseQuotationAcceptanceToken,
  parseSendQuotationForAcceptanceResult,
  parseCustomerQuotationView,
  SendQuotationForAcceptanceInputSchema,
  RevokeQuotationAcceptanceTokenInputSchema,
  RecordQuotationCustomerDecisionInputSchema,
} from "./quotation-acceptance.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const QUOTATION_ID = "323e4567-e89b-12d3-a456-426614174000";
const TOKEN_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("parseQuotationAcceptanceToken", () => {
  test("maps an active, un-revoked, un-consumed token", () => {
    const token = parseQuotationAcceptanceToken({
      id: TOKEN_ID,
      tenant_id: TENANT_ID,
      quotation_id: QUOTATION_ID,
      status: "active",
      channel: "email",
      recipient_contact_id: null,
      recipient_email: "jane@contoso.test",
      expires_at: "2026-08-24T00:00:00.000Z",
      sent_at: "2026-07-24T00:00:00.000Z",
      sent_by: "tester",
      revoked_at: null,
      revoked_reason: null,
      consumed_at: null,
      created_by: "tester",
      created_at: "2026-07-24T00:00:00.000Z",
    });
    assert.equal(token.status, "active");
    assert.equal(token.consumedAt, null);
  });
});

describe("parseSendQuotationForAcceptanceResult", () => {
  test("maps the raw-token-bearing result", () => {
    const result = parseSendQuotationForAcceptanceResult({
      token_id: TOKEN_ID,
      raw_token: "deadbeef",
      expires_at: "2026-08-24T00:00:00.000Z",
      quotation_id: QUOTATION_ID,
    });
    assert.equal(result.rawToken, "deadbeef");
    assert.equal(result.tokenId, TOKEN_ID);
  });
});

describe("parseCustomerQuotationView", () => {
  test("maps the customer-safe projection, defaulting missing jsonb to an empty object", () => {
    const view = parseCustomerQuotationView({
      token_status: "active",
      quotation_id: QUOTATION_ID,
      quote_number: "QTN-2026-000001",
      customer_snapshot: { legal_name: "Contoso Ltd" },
      currency: "IDR",
      validity_to: "2026-08-24T00:00:00.000Z",
      terms: null,
      subtotal_amount: 15000000,
      discount_amount: 0,
      tax_amount: 0,
      total_amount: 15000000,
      already_decided: false,
    });
    assert.equal(view.tokenStatus, "active");
    assert.deepEqual(view.terms, {});
    assert.equal(view.alreadyDecided, false);
  });
});

describe("SendQuotationForAcceptanceInputSchema", () => {
  test("defaults recipientContactId to null and channel to email", () => {
    const parsed = SendQuotationForAcceptanceInputSchema.parse({ quotationId: QUOTATION_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester" });
    assert.equal(parsed.recipientContactId, null);
    assert.equal(parsed.channel, "email");
  });

  test("rejects an unknown channel", () => {
    assert.throws(() => SendQuotationForAcceptanceInputSchema.parse({ quotationId: QUOTATION_ID, channel: "sms", actorAuthUserId: ACTOR_ID, actorLabel: "tester" }));
  });
});

describe("RevokeQuotationAcceptanceTokenInputSchema", () => {
  test("rejects an empty reason", () => {
    assert.throws(() => RevokeQuotationAcceptanceTokenInputSchema.parse({ tokenId: TOKEN_ID, actorAuthUserId: ACTOR_ID, actorLabel: "tester", reason: "" }));
  });
});

describe("RecordQuotationCustomerDecisionInputSchema", () => {
  test("accepts an accept decision with no reason", () => {
    const parsed = RecordQuotationCustomerDecisionInputSchema.parse({ rawToken: "deadbeef", decision: "accepted", decidedByName: "Jane Doe" });
    assert.equal(parsed.decision, "accepted");
    assert.equal(parsed.reason, null);
  });

  test("rejects an empty decidedByName", () => {
    assert.throws(() => RecordQuotationCustomerDecisionInputSchema.parse({ rawToken: "deadbeef", decision: "accepted", decidedByName: "" }));
  });

  test("rejects a decision value outside accepted/rejected", () => {
    assert.throws(() => RecordQuotationCustomerDecisionInputSchema.parse({ rawToken: "deadbeef", decision: "maybe", decidedByName: "Jane Doe" }));
  });
});
