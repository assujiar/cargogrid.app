import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  prepareFinanceInvoiceFromReadiness,
  submitFinanceInvoiceForApproval,
  discardFinanceInvoiceDraft,
  approveFinanceInvoice,
  issueFinanceInvoice,
  InvoiceMutationError,
  type InvoiceMutationRpcClient,
} from "./invoice.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const HANDOFF_ID = "323e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

const INVOICE_ROW = {
  id: INVOICE_ID, tenant_id: TENANT_ID, company_id: null, invoice_number: null,
  customer_account_id: TENANT_ID, job_order_id: TENANT_ID, billing_readiness_handoff_id: HANDOFF_ID,
  currency: "IDR", status: "draft", subtotal_amount: "15000000.00", tax_amount: "0.00", total_amount: "15000000.00",
  payment_term_days: 30, issue_date: null, due_date: null, posting_period_id: null, ar_open_item_id: null,
  submitted_by: null, submitted_at: null, approved_by: null, approved_at: null, issued_by: null, issued_at: null,
  void_reason: null, voided_by: null, voided_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): InvoiceMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as InvoiceMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("prepareFinanceInvoiceFromReadiness", () => {
  test("calls prepare_finance_invoice_from_readiness with the exact snake_case params", async () => {
    const client = fakeClient({ data: INVOICE_ROW, error: null });
    await prepareFinanceInvoiceFromReadiness(client, { tenantId: TENANT_ID, billingReadinessHandoffId: HANDOFF_ID, taxCode: "PPN", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(client.calls[0]?.fn, "prepare_finance_invoice_from_readiness");
    assert.equal(client.calls[0]?.args.p_tax_code, "PPN");
  });

  test("wraps a finance_tax_rule_missing error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_tax_rule_missing: no approved tax rule for PPH23 covers 2026-03-15" } });
    await assert.rejects(
      () => prepareFinanceInvoiceFromReadiness(client, { tenantId: TENANT_ID, billingReadinessHandoffId: HANDOFF_ID, taxCode: "PPH23", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof InvoiceMutationError && error.code === "finance_tax_rule_missing",
    );
  });
});

describe("submitFinanceInvoiceForApproval / discardFinanceInvoiceDraft / approveFinanceInvoice", () => {
  test("submitFinanceInvoiceForApproval calls submit_finance_invoice_for_approval", async () => {
    const client = fakeClient({ data: { ...INVOICE_ROW, status: "submitted" }, error: null });
    const invoice = await submitFinanceInvoiceForApproval(client, { invoiceId: INVOICE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fe" });
    assert.equal(invoice.status, "submitted");
  });

  test("discardFinanceInvoiceDraft wraps a finance_invoice_not_cancellable error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_invoice_not_cancellable: invoice is issued, only a draft or submitted invoice may be discarded" } });
    await assert.rejects(
      () => discardFinanceInvoiceDraft(client, { invoiceId: INVOICE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof InvoiceMutationError && error.code === "finance_invoice_not_cancellable",
    );
  });

  test("approveFinanceInvoice wraps a finance_invoice_not_submitted error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_invoice_not_submitted: invoice is draft not submitted" } });
    await assert.rejects(
      () => approveFinanceInvoice(client, { invoiceId: INVOICE_ID, expectedVersion: 1, actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof InvoiceMutationError && error.code === "finance_invoice_not_submitted",
    );
  });
});

describe("issueFinanceInvoice", () => {
  test("calls issue_finance_invoice with the exact snake_case params", async () => {
    const client = fakeClient({ data: { ...INVOICE_ROW, status: "issued", invoice_number: "INV-2026-000001" }, error: null });
    const invoice = await issueFinanceInvoice(client, { invoiceId: INVOICE_ID, expectedVersion: 3, issueDate: "2026-03-15", actorAuthUserId: ACTOR_ID, actorLabel: "fm" });
    assert.equal(invoice.status, "issued");
    assert.equal(client.calls[0]?.args.p_issue_date, "2026-03-15");
  });

  test("wraps a finance_invoice_period_not_open error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_invoice_period_not_open: fiscal period 2026-03 is not open" } });
    await assert.rejects(
      () => issueFinanceInvoice(client, { invoiceId: INVOICE_ID, expectedVersion: 3, issueDate: "2026-03-15", actorAuthUserId: ACTOR_ID, actorLabel: "fm" }),
      (error: unknown) => error instanceof InvoiceMutationError && error.code === "finance_invoice_period_not_open",
    );
  });
});
