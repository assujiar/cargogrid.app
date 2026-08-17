import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { getCustomerPortalPaymentStatus, listCustomerPortalReceipts, CustomerPortalPaymentQueryError, type CustomerPortalPaymentQueryClient } from "./customer-portal-payment.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "723e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "823e4567-e89b-12d3-a456-426614174000";
const RECEIPT_ID = "923e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "a23e4567-e89b-12d3-a456-426614174000";

function fakeRpcClient(response: { data: unknown; error: { message: string } | null }): {
  client: CustomerPortalPaymentQueryClient;
  calls: { fn: string; args: Record<string, unknown> }[];
} {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CustomerPortalPaymentQueryClient;
  return { client, calls };
}

describe("getCustomerPortalPaymentStatus", () => {
  test("maps a posted, partially-paid AR item with two applied allocations, coercing string amounts and reading camelCase jsonb keys", async () => {
    const { client, calls } = fakeRpcClient({
      data: [
        {
          payment_status: "partial",
          original_amount: "1100.00",
          open_amount: "400.00",
          is_held: false,
          allocations: [
            { receiptReference: "RCPT-0001", receiptDate: "2026-08-01", amount: 700, currency: "USD" },
            { receiptReference: null, receiptDate: "2026-08-05", amount: "100.00", currency: "USD" },
          ],
        },
      ],
      error: null,
    });
    const result = await getCustomerPortalPaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.paymentStatus, "partial");
    assert.equal(result.originalAmount, 1100);
    assert.equal(result.openAmount, 400);
    assert.equal(result.isHeld, false);
    assert.equal(result.allocations.length, 2);
    assert.equal(result.allocations[0]?.receiptReference, "RCPT-0001");
    assert.equal(result.allocations[0]?.amount, 700);
    assert.equal(result.allocations[1]?.receiptReference, null);
    assert.equal(result.allocations[1]?.amount, 100);
    assert.deepEqual(calls[0], {
      fn: "get_customer_portal_payment_status",
      args: { p_tenant_id: TENANT_ID, p_actor_auth_user_id: ACTOR_ID, p_invoice_id: INVOICE_ID },
    });
  });

  test("never surfaces bankAccountLabel/payerName/holdReason/arOpenItemId even if a malformed row somehow carried them -- the schema strips unknown keys", async () => {
    const { client } = fakeRpcClient({
      data: [
        {
          payment_status: "open",
          original_amount: "50.00",
          open_amount: "50.00",
          is_held: true,
          hold_reason: "internal collections note -- must never leak",
          ar_open_item_id: "leaked-id",
          allocations: [{ receiptReference: "RCPT-X", receiptDate: "2026-08-01", amount: 10, currency: "USD", bankAccountLabel: "SECRET-BANK", payerName: "Secret Payer" }],
        },
      ],
      error: null,
    });
    const result = await getCustomerPortalPaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.ok(!("holdReason" in result));
    assert.ok(!("arOpenItemId" in result));
    assert.ok(!("bankAccountLabel" in result.allocations[0]!));
    assert.ok(!("payerName" in result.allocations[0]!));
    assert.equal(JSON.stringify(result).includes("SECRET-BANK"), false);
  });

  test("maps the not_posted synthesized row (a void-before-ever-issued invoice) with null amounts and an empty allocations array, not fabricated values", async () => {
    const { client } = fakeRpcClient({ data: [{ payment_status: "not_posted", original_amount: null, open_amount: null, is_held: null, allocations: [] }], error: null });
    const result = await getCustomerPortalPaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID);
    assert.equal(result.paymentStatus, "not_posted");
    assert.equal(result.originalAmount, null);
    assert.equal(result.openAmount, null);
    assert.equal(result.isHeld, null);
    assert.deepEqual(result.allocations, []);
  });

  test("propagates record_not_found with .code set -- the identical anti-enumerating shape app.get_customer_portal_invoice already raises", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted invoice exists for x" } });
    await assert.rejects(
      () => getCustomerPortalPaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalPaymentQueryError);
        assert.equal(err.code, "record_not_found");
        return true;
      },
    );
  });

  test("does NOT call a separate denial-audit RPC on record_not_found -- a dependent read of an already-audited invoice gate", async () => {
    const { client, calls } = fakeRpcClient({ data: null, error: { message: "record_not_found: no permitted invoice exists for x" } });
    await assert.rejects(() => getCustomerPortalPaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID));
    assert.equal(calls.length, 1);
  });

  test("propagates actor_identity_mismatch", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "actor_identity_mismatch: session does not match claimed actor" } });
    await assert.rejects(
      () => getCustomerPortalPaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalPaymentQueryError);
        assert.equal(err.code, "actor_identity_mismatch");
        return true;
      },
    );
  });

  test("throws query_failed when the RPC returns no row at all", async () => {
    const { client } = fakeRpcClient({ data: [], error: null });
    await assert.rejects(
      () => getCustomerPortalPaymentStatus(client, TENANT_ID, ACTOR_ID, INVOICE_ID),
      (err: unknown) => {
        assert.ok(err instanceof CustomerPortalPaymentQueryError);
        assert.equal(err.code, "query_failed");
        return true;
      },
    );
  });
});

const RECEIPT_ROW = {
  id: RECEIPT_ID,
  customer_account_id: ACCOUNT_ID,
  receipt_reference: "RCPT-0001",
  receipt_date: "2026-08-01",
  currency: "USD",
  amount: "700.00",
  allocated_amount: "700.00",
  unapplied_amount: "0.00",
  status: "captured",
  record_version: 1,
  updated_at: "2026-08-17T00:00:00.000Z",
};

describe("listCustomerPortalReceipts", () => {
  test("maps rows, coercing string money fields, defaults filters to null and limit to 50, forwards cursor params", async () => {
    const { client, calls } = fakeRpcClient({ data: [RECEIPT_ROW], error: null });
    const result = await listCustomerPortalReceipts(client, TENANT_ID, ACTOR_ID, { cursorUpdatedAt: "2026-08-01T00:00:00.000Z", cursorId: RECEIPT_ID });
    assert.equal(result.length, 1);
    assert.equal(result[0]?.amount, 700);
    assert.equal(result[0]?.unappliedAmount, 0);
    assert.equal(result[0]?.status, "captured");
    assert.deepEqual(calls[0]?.args, {
      p_tenant_id: TENANT_ID,
      p_actor_auth_user_id: ACTOR_ID,
      p_status_filter: null,
      p_cursor_updated_at: "2026-08-01T00:00:00.000Z",
      p_cursor_id: RECEIPT_ID,
      p_limit: 50,
    });
  });

  test("never surfaces bankAccountLabel/payerName even if a malformed row somehow carried them -- the schema strips unknown keys", async () => {
    const { client } = fakeRpcClient({ data: [{ ...RECEIPT_ROW, bank_account_label: "SECRET-BANK-LABEL", payer_name: "Secret Payer" }], error: null });
    const result = await listCustomerPortalReceipts(client, TENANT_ID, ACTOR_ID);
    assert.ok(!("bankAccountLabel" in result[0]!));
    assert.ok(!("payerName" in result[0]!));
    assert.equal(JSON.stringify(result).includes("SECRET-BANK-LABEL"), false);
  });

  test("forwards statusFilter and a custom limit", async () => {
    const { client, calls } = fakeRpcClient({ data: [], error: null });
    await listCustomerPortalReceipts(client, TENANT_ID, ACTOR_ID, { statusFilter: "void", limit: 10 });
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
    const result = await listCustomerPortalReceipts(client, TENANT_ID, ACTOR_ID);
    assert.deepEqual(result, []);
  });

  test("propagates a non-record_not_found RPC error (e.g. invalid_cursor)", async () => {
    const { client } = fakeRpcClient({ data: null, error: { message: "invalid_cursor: p_cursor_updated_at is required when p_cursor_id is supplied" } });
    await assert.rejects(() => listCustomerPortalReceipts(client, TENANT_ID, ACTOR_ID, { cursorId: RECEIPT_ID }));
  });
});
