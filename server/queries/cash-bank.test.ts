import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { listFinanceBankAccounts, listFinanceBankTransactions, getFinanceCashPosition, CashBankQueryError, type CashBankQueryRpcClient } from "./cash-bank.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174001";
const GL_ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): CashBankQueryRpcClient {
  return { async rpc() { return response; } } as unknown as CashBankQueryRpcClient;
}

describe("listFinanceBankAccounts", () => {
  test("maps rows to camelCase", async () => {
    const client = fakeClient({
      data: [{
        id: ACCOUNT_ID, tenant_id: TENANT_ID, company_id: null, account_name: "Main Operating", bank_name: "Acme Bank",
        account_number_last4: "1234", currency: "USD", gl_account_id: GL_ACCOUNT_ID, status: "active",
        record_version: 1, created_by: "treasurer", created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
      }],
      error: null,
    });
    const rows = await listFinanceBankAccounts(client, { tenantId: TENANT_ID, companyId: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.accountName, "Main Operating");
  });

  test("throws on rpc error", async () => {
    const client = fakeClient({ data: null, error: { message: "insufficient_authority: lacks FIN:View" } });
    await assert.rejects(() => listFinanceBankAccounts(client, { tenantId: TENANT_ID, companyId: null, actorAuthUserId: ACTOR_ID }), CashBankQueryError);
  });
});

describe("listFinanceBankTransactions", () => {
  test("maps transaction rows to camelCase", async () => {
    const client = fakeClient({
      data: [{
        id: "523e4567-e89b-12d3-a456-426614174003", batch_id: "523e4567-e89b-12d3-a456-426614174002", tenant_id: TENANT_ID,
        bank_account_id: ACCOUNT_ID, transaction_date: "2026-07-01", direction: "credit", amount: "500.00", reference: "REF-1",
        description: null, match_status: "unmatched", matched_source_type: null, matched_source_id: null, matched_by: null,
        matched_at: null, unmatch_reason: null, record_version: 1, created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
      }],
      error: null,
    });
    const rows = await listFinanceBankTransactions(client, { tenantId: TENANT_ID, bankAccountId: null, matchStatus: null, actorAuthUserId: ACTOR_ID });
    assert.equal(rows.length, 1);
    assert.equal(rows[0]?.matchStatus, "unmatched");
  });
});

describe("getFinanceCashPosition", () => {
  test("maps the first returned row to camelCase", async () => {
    const client = fakeClient({ data: [{ bank_account_id: ACCOUNT_ID, currency: "USD", statement_balance: "500.00", gl_balance: "480.00", variance_amount: "-20.00" }], error: null });
    const position = await getFinanceCashPosition(client, { tenantId: TENANT_ID, bankAccountId: ACCOUNT_ID, asOfDate: "2026-07-15", actorAuthUserId: ACTOR_ID });
    assert.equal(position.varianceAmount, -20);
  });

  test("throws when no row is returned", async () => {
    const client = fakeClient({ data: [], error: null });
    await assert.rejects(() => getFinanceCashPosition(client, { tenantId: TENANT_ID, bankAccountId: ACCOUNT_ID, asOfDate: "2026-07-15", actorAuthUserId: ACTOR_ID }), CashBankQueryError);
  });
});
