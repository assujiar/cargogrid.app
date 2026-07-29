import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseFinanceDashboardBillingRow, parseFinanceDashboardReconciliationRow, parseFinanceDashboardCashRow } from "./finance-dashboard.ts";

describe("parseFinanceDashboardBillingRow", () => {
  test("maps a grouped billing row", () => {
    const row = parseFinanceDashboardBillingRow({ status: "issued", currency: "IDR", invoice_count: "1", total_amount: "16000000.00" });
    assert.equal(row.status, "issued");
    assert.equal(row.invoiceCount, 1);
    assert.equal(row.totalAmount, 16000000);
  });
});

describe("parseFinanceDashboardReconciliationRow", () => {
  test("maps a scope status row", () => {
    const row = parseFinanceDashboardReconciliationRow({
      scope: "ar", as_of_date: "2026-04-01", status: "completed", is_within_tolerance: true, variance_amount: "0.00", checked_at: "2026-04-01T00:00:00.000Z",
    });
    assert.equal(row.scope, "ar");
    assert.equal(row.isWithinTolerance, true);
    assert.equal(row.varianceAmount, 0);
  });
});

describe("parseFinanceDashboardCashRow", () => {
  test("maps a currency-grouped cash row", () => {
    const row = parseFinanceDashboardCashRow({ currency: "IDR", account_count: "1", statement_balance: "0.00", gl_balance: "0.00", variance_amount: "0.00" });
    assert.equal(row.currency, "IDR");
    assert.equal(row.accountCount, 1);
    assert.equal(row.statementBalance, 0);
  });
});
