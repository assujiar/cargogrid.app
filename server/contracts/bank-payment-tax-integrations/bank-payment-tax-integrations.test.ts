import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parseFinancePaymentGatewayEvent,
  parseIngestFinancePaymentGatewayWebhookEventResult,
  parseFinanceProviderDispatchInfo,
  parseFinanceProviderConnectionForSync,
  parseFinanceProviderCallEvidence,
  RecordEinvoiceSubmissionAttemptInputSchema,
  RecordTaxAuthorityLookupInputSchema,
  ReviewFinancePaymentGatewayEventInputSchema,
} from "./bank-payment-tax-integrations.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const CONNECTION_ID = "323e4567-e89b-12d3-a456-426614174000";
const EVENT_ID = "423e4567-e89b-12d3-a456-426614174000";
const BANK_TRANSACTION_ID = "523e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "523e4567-e89b-12d3-a456-426614174001";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("parseFinancePaymentGatewayEvent", () => {
  test("maps snake_case columns to camelCase for a matched event", () => {
    const event = parseFinancePaymentGatewayEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      connection_id: CONNECTION_ID,
      provider_event_id: "evt-1",
      event_type: "payment_confirmed",
      external_reference: "PAY-REF-1",
      bank_transaction_id: BANK_TRANSACTION_ID,
      match_status: "matched",
      raw_payload: { event_id: "evt-1" },
      processing_status: "received",
      review_notes: null,
      reviewed_by_auth_user_id: null,
      reviewed_at: null,
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(event.matchStatus, "matched");
    assert.equal(event.bankTransactionId, BANK_TRANSACTION_ID);
  });

  test("an unmatched event carries a null bankTransactionId, not a crash", () => {
    const event = parseFinancePaymentGatewayEvent({
      id: EVENT_ID,
      tenant_id: TENANT_ID,
      connection_id: CONNECTION_ID,
      provider_event_id: "evt-2",
      event_type: "payment_failed",
      external_reference: "UNKNOWN-REF",
      bank_transaction_id: null,
      match_status: "unmatched",
      raw_payload: {},
      processing_status: "received",
      review_notes: null,
      reviewed_by_auth_user_id: null,
      reviewed_at: null,
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(event.bankTransactionId, null);
    assert.equal(event.matchStatus, "unmatched");
  });
});

describe("parseIngestFinancePaymentGatewayWebhookEventResult", () => {
  test("maps an ok result", () => {
    const result = parseIngestFinancePaymentGatewayWebhookEventResult({ ingest_status: "ok", event_id: EVENT_ID });
    assert.equal(result.ingestStatus, "ok");
    assert.equal(result.eventId, EVENT_ID);
  });
});

describe("parseFinanceProviderDispatchInfo / parseFinanceProviderConnectionForSync", () => {
  test("both map snake_case columns to camelCase", () => {
    const dispatch = parseFinanceProviderDispatchInfo({ connection_id: CONNECTION_ID, connection_status: "active", connection_config: { apiUrl: "https://bank.example.test" } });
    assert.equal(dispatch.connectionStatus, "active");

    const sync = parseFinanceProviderConnectionForSync({ tenant_id: TENANT_ID, adapter_code: "bank_feed_api", connection_status: "active", connection_config: { pollUrl: "https://bank.example.test/poll" } });
    assert.equal(sync.adapterCode, "bank_feed_api");
  });
});

describe("parseFinanceProviderCallEvidence", () => {
  test("an e-invoice submission row carries a financeInvoiceId and null tax fields", () => {
    const evidence = parseFinanceProviderCallEvidence({
      id: "723e4567-e89b-12d3-a456-426614174000", tenant_id: TENANT_ID, connection_id: CONNECTION_ID, call_type: "einvoice_submission",
      finance_invoice_id: INVOICE_ID, tax_code: null, as_of_date: null, request_payload: {}, status: "success", response_payload: { providerReference: "EINV-1" },
      provider_unit_cost_amount: 0.01, currency: "USD", billed_amount: 0.012, error_message: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "system",
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(evidence.callType, "einvoice_submission");
    assert.equal(evidence.financeInvoiceId, INVOICE_ID);
    assert.equal(evidence.taxCode, null);
  });

  test("a tax authority lookup row carries taxCode/asOfDate and a null financeInvoiceId", () => {
    const evidence = parseFinanceProviderCallEvidence({
      id: "723e4567-e89b-12d3-a456-426614174001", tenant_id: TENANT_ID, connection_id: CONNECTION_ID, call_type: "tax_authority_lookup",
      finance_invoice_id: null, tax_code: "PPN", as_of_date: "2026-08-21", request_payload: {}, status: "success", response_payload: { rateValue: 0.11 },
      provider_unit_cost_amount: 0.01, currency: "USD", billed_amount: 0.012, error_message: null, requested_by_auth_user_id: ACTOR_ID, requested_by: "system",
      created_at: "2026-08-21T00:00:00.000Z",
    });
    assert.equal(evidence.callType, "tax_authority_lookup");
    assert.equal(evidence.taxCode, "PPN");
    assert.equal(evidence.financeInvoiceId, null);
  });
});

describe("RecordEinvoiceSubmissionAttemptInputSchema", () => {
  test("defaults optional fields to null", () => {
    const parsed = RecordEinvoiceSubmissionAttemptInputSchema.parse({
      tenantId: TENANT_ID, connectionId: CONNECTION_ID, financeInvoiceId: INVOICE_ID, status: "success", requestPayload: {}, actorAuthUserId: ACTOR_ID, actorLabel: "system",
    });
    assert.equal(parsed.responsePayload, null);
    assert.equal(parsed.providerUnitCostAmount, null);
  });

  test("rejects a negative cost", () => {
    assert.throws(() =>
      RecordEinvoiceSubmissionAttemptInputSchema.parse({
        tenantId: TENANT_ID, connectionId: CONNECTION_ID, financeInvoiceId: INVOICE_ID, status: "success", requestPayload: {},
        providerUnitCostAmount: -1, actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });
});

describe("RecordTaxAuthorityLookupInputSchema", () => {
  test("requires a non-empty taxCode", () => {
    assert.throws(() =>
      RecordTaxAuthorityLookupInputSchema.parse({
        tenantId: TENANT_ID, connectionId: CONNECTION_ID, taxCode: "", asOfDate: "2026-08-21", status: "success", requestPayload: {}, actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });
});

describe("ReviewFinancePaymentGatewayEventInputSchema", () => {
  test("rejects a decision outside reviewed/dismissed", () => {
    assert.throws(() =>
      ReviewFinancePaymentGatewayEventInputSchema.parse({
        eventId: EVENT_ID, decision: "approved", actorAuthUserId: ACTOR_ID, actorLabel: "system",
      }),
    );
  });

  test("defaults notes to null", () => {
    const parsed = ReviewFinancePaymentGatewayEventInputSchema.parse({
      eventId: EVENT_ID, decision: "reviewed", actorAuthUserId: ACTOR_ID, actorLabel: "system",
    });
    assert.equal(parsed.notes, null);
  });
});
