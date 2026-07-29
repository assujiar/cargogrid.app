import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceInvoiceStatusSchema,
  FinanceInvoiceLineTypeSchema,
  PrepareFinanceInvoiceFromReadinessInputSchema,
  IssueFinanceInvoiceInputSchema,
  parseFinanceInvoice,
  parseFinanceInvoiceLine,
} from "./invoice.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "323e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("FinanceInvoiceStatusSchema / FinanceInvoiceLineTypeSchema", () => {
  test("accepts the five canonical lifecycle states", () => {
    for (const status of ["draft", "submitted", "approved", "issued", "void"]) {
      assert.doesNotThrow(() => FinanceInvoiceStatusSchema.parse(status));
    }
  });

  test("accepts only charge/tax as line types", () => {
    assert.doesNotThrow(() => FinanceInvoiceLineTypeSchema.parse("charge"));
    assert.doesNotThrow(() => FinanceInvoiceLineTypeSchema.parse("tax"));
    assert.throws(() => FinanceInvoiceLineTypeSchema.parse("discount"));
  });
});

describe("PrepareFinanceInvoiceFromReadinessInputSchema", () => {
  test("defaults paymentTermDays to 30 and taxCode to null", () => {
    const parsed = PrepareFinanceInvoiceFromReadinessInputSchema.parse({
      tenantId: TENANT_ID, billingReadinessHandoffId: HANDOFF_ID, actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(parsed.paymentTermDays, 30);
    assert.equal(parsed.taxCode, null);
  });
});

describe("IssueFinanceInvoiceInputSchema", () => {
  test("requires an issueDate", () => {
    assert.throws(() => IssueFinanceInvoiceInputSchema.parse({ invoiceId: INVOICE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }));
    assert.doesNotThrow(() => IssueFinanceInvoiceInputSchema.parse({ invoiceId: INVOICE_ID, expectedVersion: 1, issueDate: "2026-03-15", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }));
  });
});

describe("parseFinanceInvoice", () => {
  test("maps a raw snake_case row, coercing string amounts", () => {
    const parsed = parseFinanceInvoice({
      id: INVOICE_ID, tenant_id: TENANT_ID, company_id: null, invoice_number: "INV-2026-000001",
      customer_account_id: ACCOUNT_ID, job_order_id: JOB_ID, billing_readiness_handoff_id: HANDOFF_ID,
      currency: "IDR", status: "issued", subtotal_amount: "15000000.00", tax_amount: "1650000.00", total_amount: "16650000.00",
      payment_term_days: 30, issue_date: "2026-03-15", due_date: "2026-04-14", posting_period_id: null, ar_open_item_id: null,
      submitted_by: "fe", submitted_at: "2026-03-14T00:00:00.000Z", approved_by: "fm", approved_at: "2026-03-14T00:00:00.000Z",
      issued_by: "fm", issued_at: "2026-03-15T00:00:00.000Z", void_reason: null, voided_by: null, voided_at: null,
      record_version: 4, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-15T00:00:00.000Z",
    });
    assert.equal(parsed.totalAmount, 16650000);
    assert.equal(parsed.status, "issued");
  });
});

describe("parseFinanceInvoiceLine", () => {
  test("maps a raw snake_case line row", () => {
    const parsed = parseFinanceInvoiceLine({
      id: INVOICE_ID, invoice_id: INVOICE_ID, line_number: 1, line_type: "charge",
      description: "Freight and service charges per Job Order JOB-2026-000001", amount: "15000000.00",
      tax_code_id: null, tax_rule_version_id: null, created_at: "2026-03-10T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 15000000);
    assert.equal(parsed.lineType, "charge");
  });
});
