import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  createFinanceBankAccount,
  importFinanceBankStatement,
  matchFinanceBankTransaction,
  unmatchFinanceBankTransaction,
  CashBankMutationError,
  type CashBankMutationRpcClient,
} from "./cash-bank.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174001";
const GL_ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const BATCH_ID = "523e4567-e89b-12d3-a456-426614174002";
const TRANSACTION_ID = "523e4567-e89b-12d3-a456-426614174003";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

const ACCOUNT_ROW = {
  id: ACCOUNT_ID, tenant_id: TENANT_ID, company_id: null, account_name: "Main Operating", bank_name: "Acme Bank",
  account_number_last4: "1234", currency: "USD", gl_account_id: GL_ACCOUNT_ID, status: "active",
  record_version: 1, created_by: "treasurer", created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
};

const BATCH_ROW = {
  id: BATCH_ID, tenant_id: TENANT_ID, bank_account_id: ACCOUNT_ID, source_reference: "stmt-1", line_count: 2,
  imported_by: "treasurer", imported_at: "2026-07-01T00:00:00.000Z",
};

const TRANSACTION_ROW = {
  id: TRANSACTION_ID, batch_id: BATCH_ID, tenant_id: TENANT_ID, bank_account_id: ACCOUNT_ID, transaction_date: "2026-07-01",
  direction: "credit", amount: "500.00", reference: "REF-1", description: null, match_status: "unmatched",
  matched_source_type: null, matched_source_id: null, matched_by: null, matched_at: null, unmatch_reason: null,
  record_version: 1, created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
};

function fakeClient(response: { data: unknown; error: { message: string } | null }): CashBankMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  return {
    calls,
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as CashBankMutationRpcClient & { calls: { fn: string; args: Record<string, unknown> }[] };
}

describe("createFinanceBankAccount", () => {
  test("calls create_finance_bank_account with exact snake_case params", async () => {
    const client = fakeClient({ data: ACCOUNT_ROW, error: null });
    await createFinanceBankAccount(client, {
      tenantId: TENANT_ID, accountName: "Main Operating", bankName: "Acme Bank", accountNumberLast4: "1234",
      currency: "USD", glAccountId: GL_ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "treasurer",
    });
    assert.equal(client.calls[0]?.fn, "create_finance_bank_account");
    assert.equal(client.calls[0]?.args.p_account_number_last4, "1234");
  });

  test("wraps a finance_cash_gl_account_not_postable error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_cash_gl_account_not_postable: account CASH is not active/postable" } });
    await assert.rejects(
      () => createFinanceBankAccount(client, {
        tenantId: TENANT_ID, accountName: "Main Operating", bankName: "Acme Bank", accountNumberLast4: "1234",
        currency: "USD", glAccountId: GL_ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "treasurer",
      }),
      (error: unknown) => error instanceof CashBankMutationError && error.code === "finance_cash_gl_account_not_postable",
    );
  });
});

describe("importFinanceBankStatement", () => {
  test("calls import_finance_bank_statement with mapped lines", async () => {
    const client = fakeClient({ data: BATCH_ROW, error: null });
    const batch = await importFinanceBankStatement(client, {
      tenantId: TENANT_ID, bankAccountId: ACCOUNT_ID, sourceReference: "stmt-1",
      lines: [{ transactionDate: "2026-07-01", direction: "credit", amount: 500 }],
      actorAuthUserId: ACTOR_ID, actorLabel: "treasurer",
    });
    assert.equal(client.calls[0]?.fn, "import_finance_bank_statement");
    assert.equal(batch.lineCount, 2);
  });
});

describe("matchFinanceBankTransaction / unmatchFinanceBankTransaction", () => {
  test("matchFinanceBankTransaction calls match_finance_bank_transaction", async () => {
    const client = fakeClient({ data: { ...TRANSACTION_ROW, match_status: "matched", matched_source_type: "receipt" }, error: null });
    const transaction = await matchFinanceBankTransaction(client, {
      transactionId: TRANSACTION_ID, expectedVersion: 1, matchedSourceType: "receipt", matchedSourceId: null, actorAuthUserId: ACTOR_ID, actorLabel: "treasurer",
    });
    assert.equal(transaction.matchStatus, "matched");
  });

  test("unmatchFinanceBankTransaction wraps a finance_cash_unmatch_reason_required error", async () => {
    const client = fakeClient({ data: null, error: { message: "finance_cash_unmatch_reason_required: a non-empty reason is required" } });
    await assert.rejects(
      () => unmatchFinanceBankTransaction(client, { transactionId: TRANSACTION_ID, expectedVersion: 1, reason: "x", actorAuthUserId: ACTOR_ID, actorLabel: "treasurer" }),
      (error: unknown) => error instanceof CashBankMutationError && error.code === "finance_cash_unmatch_reason_required",
    );
  });
});
