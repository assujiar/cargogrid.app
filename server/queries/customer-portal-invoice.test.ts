import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  getCustomerPortalInvoice,
  listCustomerPortalInvoices,
  getCustomerPortalInvoiceLines,
  getCustomerPortalInvoicePaymentStatus,
  CustomerPortalInvoiceQueryError,
  type CustomerPortalInvoiceQueryClient,
} from "./customer-portal-invoice.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "823e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalInvoiceQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalInvoiceQueryClient;
  return { client, calls };
}

/**
 * Kept aligned with what `app.get_customer_portal_invoice`/`app.list_customer_portal_invoices`
 * actually return after `20260827140000` added `customer_account_id` to both projections
 * (`ISS-2026-124`). A fixture that drifts from the RPC's real output column set is worth nothing —
 * `ISS-2026-315` is what that costs when the field is required rather than nullable.
 */
const ACCOUNT_ID = "523e4567-e89b-12d3-a456-426614174000";
const INVOICE_ROW = {
  id: INVOICE_ID,
  customer_account_id: ACCOUNT_ID,
  invoice_number: "INV-2026-000123",
  currency: "USD",
  status: "issued",
  subtotal_amount: "1000.00",
  tax_amount: "100.00",
  total_amount: "1100.00",
  issue_date: "2026-08-01",
  due_date: "2026-08-31",
  record_version: 1,
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("getCustomerPortalInvoice", () => {
  test("maps the RPC's own single row, coercing string money fields to numbers, and passes the exact param names", async () => {
    const { client, calls } = fakeRpcClient({ data: [INVOICE_ROW], error: null });
    const result = await getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.status, "issued");
    assert.equal(result.totalAmount, 1100);
    assert.equal(result.invoiceNumber, "INV-2026-000123");
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_invoice",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_invoice_id: INVOICE_ID },
    });
  });

  /**
   * `ISS-2026-124`: a multi-account customer saw every one of their invoices correctly but had
   * nothing in the row saying WHICH of their accounts it was for. This proves the id now reaches
   * the client — the DB half alone was invisible at the layer a customer actually looks at.
   */
  test("customerAccountId reaches the parsed row, so a multi-account reader can tell whose invoice it is", async () => {
    const { client } = fakeRpcClient({ data: [INVOICE_ROW], error: null });
    const result = await getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.customerAccountId, ACCOUNT_ID);
  });

  /** And it degrades to null rather than throwing: a listing must never fail over one absent field. */
  test("a row without customer_account_id degrades to null rather than rejecting the whole listing", async () => {
    const { customer_account_id: _dropped, ...withoutAccount } = INVOICE_ROW;
    const { client } = fakeRpcClient({ data: [withoutAccount], error: null });
    const result = await getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.customerAccountId, null);
  });

  test("propagates record_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted invoice exists for x" } });
    await assert.rejects(
      () => getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalInvoiceQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("a null invoiceNumber/issueDate/dueDate (a void-before-ever-issued invoice) is accepted, not coerced to a fabricated value", async () => {
    const { client } = fakeRpcClient({
      data: [{ ...INVOICE_ROW, status: "void", invoice_number: null, issue_date: null, due_date: null }],
      error: null,
    });
    const result = await getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.status, "void");
    assert.equal(result.invoiceNumber, null);
    assert.equal(result.issueDate, null);
    assert.equal(result.dueDate, null);
  });

  test("on record_not_found, also calls the durable denial-audit RPC with resource_type=invoice", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted invoice exists for x" } });
    await assert.rejects(() => getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID));
    assert.equal(calls.length, 2);
    assert.deepEqual(calls[1], {
      fn: "record_customer_inventory_access_denial",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_resource_type: "invoice", p_resource_id: INVOICE_ID },
    });
  });

  test("does NOT call the denial-audit RPC on a successful read", async () => {
    const { client, calls } = fakeRpcClient({ data: [INVOICE_ROW], error: null });
    await getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(calls.length, 1);
  });

  test("does NOT call the denial-audit RPC for a non-record_not_found error (e.g. actor_identity_mismatch)", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "actor_identity_mismatch: session does not match claimed actor" } });
    await assert.rejects(() => getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID));
    assert.equal(calls.length, 1);
  });

  test("a failing denial-audit call never masks the original record_not_found error", async () => {
    const calls: { fn: string; args: Record<string, unknown> }[] = [];
    const client = {
      async rpc(fn: string, args: Record<string, unknown>) {
        calls.push({ fn, args });
        if (fn === "record_customer_inventory_access_denial") {
          throw new Error("network blip");
        }
        return { data: null, error: { message: "record_not_found: no permitted invoice exists for x" } };
      },
    } as unknown as CustomerPortalInvoiceQueryClient;
    await assert.rejects(
      () => getCustomerPortalInvoice(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalInvoiceQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
    assert.equal(calls.length, 2);
  });
});

describe("listCustomerPortalInvoices", () => {
  test("defaults filters to null and limit to 50, forwards cursor params", async () => {
    const { client, calls } = fakeRpcClient({ data: [INVOICE_ROW], error: null });
    const result = await listCustomerPortalInvoices(client, TENANT_ID, ACTOR_ID, { cursorUpdatedAt: "2026-08-01T00:00:00.000Z", cursorId: INVOICE_ID });
    assert.equal(result.length, 1);
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status_filter: null,
      p_cursor_updated_at: "2026-08-01T00:00:00.000Z",
      p_cursor_id: INVOICE_ID,
      p_limit: 50,
    });
  });

  test("forwards statusFilter and a custom limit", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalInvoices(client, TENANT_ID, ACTOR_ID, { statusFilter: "void", limit: 10 });
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status_filter: "void",
      p_cursor_updated_at: null,
      p_cursor_id: null,
      p_limit: 10,
    });
  });

  test("returns an empty array when the RPC returns null data", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await listCustomerPortalInvoices(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });

  test("propagates a non-record_not_found RPC error (e.g. invalid_cursor)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied" } });
    await assert.rejects(() => listCustomerPortalInvoices(client, TENANT_ID, ACTOR_ID, { cursorId: INVOICE_ID }));
  });
});

describe("getCustomerPortalInvoiceLines", () => {
  test("maps line rows, never exposes tax_code_id/tax_rule_version_id even if the RPC somehow returned them", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        { line_number: 1, line_type: "charge", description: "Freight and service charges", amount: "1000.00" },
        { line_number: 2, line_type: "tax", description: "VAT tax", amount: "100.00", tax_code_id: "leaked-id" },
      ],
      error: null,
    });
    const result = await getCustomerPortalInvoiceLines(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.length, 2);
    assert.equal(result[1]?.amount, 100);
    assert.ok(!("taxCodeId" in result[1]!));
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_invoice_id: INVOICE_ID });
  });

  test("returns an empty array when the RPC returns null data", async () => {
    const { client } = fakeRpcClient({ data: null, error: null });
    const result = await getCustomerPortalInvoiceLines(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.deepEqual(result, []);
  });

  test("propagates record_not_found with .code set, does NOT call the denial-audit RPC", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted invoice exists for x" } });
    await assert.rejects(
      () => getCustomerPortalInvoiceLines(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalInvoiceQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
    assert.equal(calls.length, 1);
  });
});

describe("getCustomerPortalInvoicePaymentStatus", () => {
  test("maps a posted AR item's own payment status", async () => {
    const { client, calls } = fakeRpcClient({ data: [{ payment_status: "partial", original_amount: "1100.00", open_amount: "400.00", is_held: false }], error: null });
    const result = await getCustomerPortalInvoicePaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.paymentStatus, "partial");
    assert.equal(result.openAmount, 400);
    assert.equal(result.isHeld, false);
    assert.deepEqual(calls[0]?.args, { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_invoice_id: INVOICE_ID });
  });

  test("maps the not_posted synthesized row (a void-before-ever-issued invoice) with null amounts, not fabricated zeros", async () => {
    const { client } = fakeRpcClient({ data: [{ payment_status: "not_posted", original_amount: null, open_amount: null, is_held: null }], error: null });
    const result = await getCustomerPortalInvoicePaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.paymentStatus, "not_posted");
    assert.equal(result.originalAmount, null);
    assert.equal(result.openAmount, null);
    assert.equal(result.isHeld, null);
  });

  test("propagates record_not_found with .code set", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted invoice exists for x" } });
    await assert.rejects(
      () => getCustomerPortalInvoicePaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalInvoiceQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("throws query_failed when the RPC returns no row at all", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () => getCustomerPortalInvoicePaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalInvoiceQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});
