import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { IssueFinanceCreditNoteInputSchema, parseFinanceCreditNote } from "./finance-credit-note.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "323e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "423e4567-e89b-12d3-a456-426614174000";
const AR_ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";

describe("IssueFinanceCreditNoteInputSchema", () => {
  test("rejects a non-positive amount", () => {
    assert.throws(() =>
      IssueFinanceCreditNoteInputSchema.parse({
        tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 0, reason: "overcharged", creditDate: "2026-03-15", idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
    assert.throws(() =>
      IssueFinanceCreditNoteInputSchema.parse({
        tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: -300, reason: "overcharged", creditDate: "2026-03-15", idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
  });

  test("rejects an empty reason", () => {
    assert.throws(() =>
      IssueFinanceCreditNoteInputSchema.parse({
        tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 300, reason: "", creditDate: "2026-03-15", idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
  });

  test("rejects an empty idempotency key", () => {
    assert.throws(() =>
      IssueFinanceCreditNoteInputSchema.parse({
        tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 300, reason: "overcharged", creditDate: "2026-03-15", idempotencyKey: "", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
  });

  test("accepts a valid input", () => {
    assert.doesNotThrow(() =>
      IssueFinanceCreditNoteInputSchema.parse({
        tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 300, reason: "billing correction: overcharged freight", creditDate: "2026-03-15", idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
      }),
    );
  });
});

describe("parseFinanceCreditNote", () => {
  test("maps a raw snake_case row, coercing a string amount", () => {
    const parsed = parseFinanceCreditNote({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      company_id: null,
      invoice_id: INVOICE_ID,
      customer_account_id: CUSTOMER_ID,
      currency: "USD",
      amount: "300.00",
      reason: "billing correction: overcharged freight",
      ar_open_item_id: AR_ITEM_ID,
      idempotency_key: "k1",
      issued_by: "fm",
      issued_at: "2026-03-15T00:00:00.000Z",
      created_at: "2026-03-15T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 300);
    assert.equal(parsed.invoiceId, INVOICE_ID);
    assert.equal(parsed.arOpenItemId, AR_ITEM_ID);
  });

  test("maps null company_id/ar_open_item_id/issued_by to null, never fabricating a value", () => {
    const parsed = parseFinanceCreditNote({
      id: "723e4567-e89b-12d3-a456-426614174000",
      tenant_id: TENANT_ID,
      company_id: null,
      invoice_id: INVOICE_ID,
      customer_account_id: CUSTOMER_ID,
      currency: "USD",
      amount: "300.00",
      reason: "billing correction: overcharged freight",
      ar_open_item_id: null,
      idempotency_key: "k1",
      issued_by: null,
      issued_at: "2026-03-15T00:00:00.000Z",
      created_at: "2026-03-15T00:00:00.000Z",
    });
    assert.equal(parsed.companyId, null);
    assert.equal(parsed.arOpenItemId, null);
    assert.equal(parsed.issuedBy, null);
  });
});
