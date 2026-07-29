import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceInvoices, getFinanceInvoiceLines, InvoiceQueryError, type InvoiceQueryRpcClient } from "./invoice.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "623e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): InvoiceQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as InvoiceQueryRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

const INVOICE_ROW = {
  id: INVOICE_ID, tenant_id: TENANT_ID, company_id: null, invoice_number: null,
  customer_account_id: TENANT_ID, job_order_id: TENANT_ID, billing_readiness_handoff_id: TENANT_ID,
  currency: "IDR", status: "draft", subtotal_amount: "15000000.00", tax_amount: "0.00", total_amount: "15000000.00",
  payment_term_days: 30, issue_date: null, due_date: null, posting_period_id: null, ar_open_item_id: null,
  submitted_by: null, submitted_at: null, approved_by: null, approved_at: null, issued_by: null, issued_at: null,
  void_reason: null, voided_by: null, voided_at: null,
  record_version: 1, created_by: "fm", created_at: "2026-03-10T00:00:00.000Z", updated_at: "2026-03-10T00:00:00.000Z",
};

describe("listFinanceInvoices", () => {
  test("maps every returned row", async () => {
    const client = fakeRpcClient({ data: [INVOICE_ROW], error: null });
    const invoices = await listFinanceInvoices(client, { tenantId: TENANT_ID, companyId: null, customerAccountId: null, status: null, actorAuthUserId: ACTOR_ID });
    assert.equal(invoices.length, 1);
    assert.equal(invoices[0]?.status, "draft");
  });

  test("wraps a database error into a typed InvoiceQueryError", async () => {
    const client = fakeRpcClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:View for tenant" } });
    await assert.rejects(
      () => listFinanceInvoices(client, { tenantId: TENANT_ID, companyId: null, customerAccountId: null, status: null, actorAuthUserId: ACTOR_ID }),
      InvoiceQueryError,
    );
  });
});

describe("getFinanceInvoiceLines", () => {
  test("maps every returned line row", async () => {
    const client = fakeRpcClient({
      data: [{ id: INVOICE_ID, invoice_id: INVOICE_ID, line_number: 1, line_type: "charge", description: "Freight", amount: "15000000.00", tax_code_id: null, tax_rule_version_id: null, created_at: "2026-03-10T00:00:00.000Z" }],
      error: null,
    });
    const lines = await getFinanceInvoiceLines(client, { invoiceId: INVOICE_ID, actorAuthUserId: ACTOR_ID });
    assert.equal(lines.length, 1);
    assert.equal(lines[0]?.amount, 15000000);
  });
});
