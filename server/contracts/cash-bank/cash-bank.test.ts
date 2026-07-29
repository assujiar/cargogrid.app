import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceBankAccountStatusSchema,
  CreateFinanceBankAccountInputSchema,
  ImportFinanceBankStatementInputSchema,
  parseFinanceBankAccount,
  parseFinanceBankTransaction,
  parseFinanceCashPosition,
} from "./cash-bank.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const ACCOUNT_ID = "323e4567-e89b-12d3-a456-426614174001";
const GL_ACCOUNT_ID = "423e4567-e89b-12d3-a456-426614174000";
const BATCH_ID = "523e4567-e89b-12d3-a456-426614174002";
const TRANSACTION_ID = "523e4567-e89b-12d3-a456-426614174003";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";

describe("FinanceBankAccountStatusSchema", () => {
  test("accepts active/inactive", () => {
    for (const status of ["active", "inactive"]) {
      assert.doesNotThrow(() => FinanceBankAccountStatusSchema.parse(status));
    }
  });
});

describe("CreateFinanceBankAccountInputSchema", () => {
  test("requires accountNumberLast4 to be at most 4 characters", () => {
    assert.throws(() => CreateFinanceBankAccountInputSchema.parse({
      tenantId: TENANT_ID, accountName: "Main Operating", bankName: "Acme Bank", accountNumberLast4: "123456",
      currency: "USD", glAccountId: GL_ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "treasurer",
    }));
  });

  test("accepts a well-formed request", () => {
    const parsed = CreateFinanceBankAccountInputSchema.parse({
      tenantId: TENANT_ID, accountName: "Main Operating", bankName: "Acme Bank", accountNumberLast4: "1234",
      currency: "USD", glAccountId: GL_ACCOUNT_ID, actorAuthUserId: ACTOR_ID, actorLabel: "treasurer",
    });
    assert.equal(parsed.accountNumberLast4, "1234");
  });
});

describe("ImportFinanceBankStatementInputSchema", () => {
  test("requires at least one line", () => {
    assert.throws(() => ImportFinanceBankStatementInputSchema.parse({
      tenantId: TENANT_ID, bankAccountId: ACCOUNT_ID, sourceReference: "stmt-1", lines: [], actorAuthUserId: ACTOR_ID, actorLabel: "treasurer",
    }));
  });
});

describe("parseFinanceBankAccount / parseFinanceBankTransaction / parseFinanceCashPosition", () => {
  test("maps account row to camelCase", () => {
    const parsed = parseFinanceBankAccount({
      id: ACCOUNT_ID, tenant_id: TENANT_ID, company_id: null, account_name: "Main Operating", bank_name: "Acme Bank",
      account_number_last4: "1234", currency: "USD", gl_account_id: GL_ACCOUNT_ID, status: "active",
      record_version: 1, created_by: "treasurer", created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
    });
    assert.equal(parsed.accountNumberLast4, "1234");
  });

  test("maps transaction row to camelCase, coercing numeric strings", () => {
    const parsed = parseFinanceBankTransaction({
      id: TRANSACTION_ID, batch_id: BATCH_ID, tenant_id: TENANT_ID, bank_account_id: ACCOUNT_ID, transaction_date: "2026-07-01",
      direction: "credit", amount: "500.00", reference: "REF-1", description: null, match_status: "unmatched",
      matched_source_type: null, matched_source_id: null, matched_by: null, matched_at: null, unmatch_reason: null,
      record_version: 1, created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
    });
    assert.equal(parsed.amount, 500);
    assert.equal(parsed.matchStatus, "unmatched");
  });

  test("maps cash position row to camelCase, coercing numeric strings", () => {
    const parsed = parseFinanceCashPosition({ bank_account_id: ACCOUNT_ID, currency: "USD", statement_balance: "500.00", gl_balance: "500.00", variance_amount: "0.00" });
    assert.equal(parsed.varianceAmount, 0);
  });
});
