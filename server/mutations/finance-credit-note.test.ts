import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { issueFinanceCreditNote, FinanceCreditNoteMutationError, type FinanceCreditNoteMutationRpcClient } from "./finance-credit-note.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "323e4567-e89b-12d3-a456-426614174000";
const CUSTOMER_ID = "423e4567-e89b-12d3-a456-426614174000";
const AR_ITEM_ID = "523e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "623e4567-e89b-12d3-a456-426614174000";
const CREDIT_NOTE_ID = "723e4567-e89b-12d3-a456-426614174000";

const CREDIT_NOTE_ROW = {
  id: CREDIT_NOTE_ID, tenant_id: TENANT_ID, company_id: null, invoice_id: INVOICE_ID, customer_account_id: CUSTOMER_ID,
  currency: "USD", amount: "300.00", reason: "billing correction: overcharged freight", ar_open_item_id: AR_ITEM_ID,
  idempotency_key: "k1", issued_by: "fm", issued_at: "2026-03-15T00:00:00.000Z", created_at: "2026-03-15T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): FinanceCreditNoteMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as FinanceCreditNoteMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("issueFinanceCreditNote", () => {
  test("calls issue_finance_credit_note with the exact snake_case params", async () => {
    const client = fakeClient({ data: CREDIT_NOTE_ROW, error: null });
    const creditNote = await issueFinanceCreditNote(client, {
      tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 300, reason: "billing correction: overcharged freight", creditDate: "2026-03-15",
      idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
    });
    assert.equal(client.calls[0]?.fn, "issue_finance_credit_note");
    assert.equal(client.calls[0]?.args.p_amount, 300);
    assert.equal(client.calls[0]?.args.p_reason, "billing correction: overcharged freight");
    assert.equal(client.calls[0]?.args.p_credit_date, "2026-03-15");
    assert.equal(creditNote.amount, 300);
    assert.equal(creditNote.arOpenItemId, AR_ITEM_ID);
  });

  test("wraps a finance_credit_note_invoice_not_issued error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_credit_note_invoice_not_issued: invoice is draft not issued" } });
    await assert.rejects(
      () =>
        issueFinanceCreditNote(client, {
          tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 300, reason: "test", creditDate: "2026-03-15", idempotencyKey: "k1", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
        }),
      (error: unknown) => error instanceof FinanceCreditNoteMutationError && error.code === "finance_credit_note_invoice_not_issued",
    );
  });

  test("wraps a finance_credit_note_exceeds_invoice error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_credit_note_exceeds_invoice: crediting 800 would bring cumulative credits to 1100 which exceeds 1000" } });
    await assert.rejects(
      () =>
        issueFinanceCreditNote(client, {
          tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 800, reason: "test", creditDate: "2026-03-15", idempotencyKey: "k2", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
        }),
      (error: unknown) => error instanceof FinanceCreditNoteMutationError && error.code === "finance_credit_note_exceeds_invoice",
    );
  });

  test("wraps an insufficient_authority error for a caller with no FIN:Edit grant", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: identity lacks FIN:Edit for tenant" } });
    await assert.rejects(
      () =>
        issueFinanceCreditNote(client, {
          tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 10, reason: "test", creditDate: "2026-03-15", idempotencyKey: "k3", actorAuthUserId: ACTOR_ID, actorLabel: "plain",
        }),
      (error: unknown) => error instanceof FinanceCreditNoteMutationError && error.code === "insufficient_authority",
    );
  });

  test("falls back to mutation_failed for an unrecognized error code", async () => {
    const client = fakeClient({ data: null, error: { message: "some_unrelated_postgres_error: connection reset" } });
    await assert.rejects(
      () =>
        issueFinanceCreditNote(client, {
          tenantId: TENANT_ID, invoiceId: INVOICE_ID, amount: 10, reason: "test", creditDate: "2026-03-15", idempotencyKey: "k4", actorAuthUserId: ACTOR_ID, actorLabel: "fm",
        }),
      (error: unknown) => error instanceof FinanceCreditNoteMutationError && error.code === "mutation_failed",
    );
  });
});
