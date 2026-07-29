import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  FinanceAccountTypeSchema,
  FinanceNormalBalanceSchema,
  FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE,
  CreateFinanceAccountDraftInputSchema,
  parseFinanceAccount,
  parseFinanceAccountDependencyImpact,
} from "./chart-of-accounts.ts";

describe("FinanceAccountTypeSchema / FinanceNormalBalanceSchema", () => {
  test("accepts the five canonical account types", () => {
    for (const type of ["asset", "liability", "equity", "revenue", "expense"]) {
      assert.doesNotThrow(() => FinanceAccountTypeSchema.parse(type));
    }
  });

  test("FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE matches the canonical, stable mapping (Prompt 192 section 24)", () => {
    assert.equal(FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE.asset, "debit");
    assert.equal(FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE.expense, "debit");
    assert.equal(FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE.liability, "credit");
    assert.equal(FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE.equity, "credit");
    assert.equal(FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE.revenue, "credit");
  });

  test("rejects an unrecognized normal balance", () => {
    assert.throws(() => FinanceNormalBalanceSchema.parse("neutral"));
  });
});

describe("CreateFinanceAccountDraftInputSchema", () => {
  test("parses a well-formed tenant-wide account draft request", () => {
    const parsed = CreateFinanceAccountDraftInputSchema.parse({
      tenantId: "123e4567-e89b-12d3-a456-426614174000",
      code: "1200-AR",
      name: "Accounts Receivable",
      accountType: "asset",
      normalBalance: "debit",
      actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
      createdBy: "finance-admin",
    });
    assert.equal(parsed.companyId, null);
    assert.equal(parsed.isControlAccount, false);
  });

  test("rejects an invalid currency-restriction shape", () => {
    assert.throws(() =>
      CreateFinanceAccountDraftInputSchema.parse({
        tenantId: "123e4567-e89b-12d3-a456-426614174000",
        code: "1200-AR",
        name: "Accounts Receivable",
        accountType: "asset",
        normalBalance: "debit",
        currencyRestriction: "idr",
        actorAuthUserId: "223e4567-e89b-12d3-a456-426614174000",
        createdBy: "finance-admin",
      }),
    );
  });
});

describe("parseFinanceAccount", () => {
  test("maps a raw snake_case row to the camelCase contract shape", () => {
    const parsed = parseFinanceAccount({
      id: "323e4567-e89b-12d3-a456-426614174000",
      tenant_id: "123e4567-e89b-12d3-a456-426614174000",
      company_id: null,
      code: "1200-AR",
      name: "Accounts Receivable",
      account_type: "asset",
      normal_balance: "debit",
      parent_account_id: null,
      is_control_account: false,
      is_postable: true,
      currency_restriction: null,
      status: "draft",
      record_version: 1,
      created_by: "finance-admin",
      created_at: "2026-07-28T00:00:00.000Z",
      updated_at: "2026-07-28T00:00:00.000Z",
    });
    assert.equal(parsed.accountType, "asset");
    assert.equal(parsed.isPostable, true);
  });
});

describe("parseFinanceAccountDependencyImpact", () => {
  test("maps a raw dependency-impact jsonb result", () => {
    const parsed = parseFinanceAccountDependencyImpact({
      accountId: "323e4567-e89b-12d3-a456-426614174000",
      code: "1200-AR",
      activeChildAccountCount: 2,
      referencedByPublishedPostingMap: true,
    });
    assert.equal(parsed.activeChildAccountCount, 2);
    assert.equal(parsed.referencedByPublishedPostingMap, true);
  });
});
