import { test, describe } from "node:test";
import assert from "node:assert/strict";
import { parseFinanceJobProfitabilityFact, parseFinanceProfitabilitySummaryRow } from "./profitability.ts";

const TENANT_ID = "223e4567-e89b-12d3-a456-426614174000";
const JOB_ID = "323e4567-e89b-12d3-a456-426614174000";
const FACT_ID = "423e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "523e4567-e89b-12d3-a456-426614174000";
const INVOICE_ID = "623e4567-e89b-12d3-a456-426614174000";
const COST_ID = "723e4567-e89b-12d3-a456-426614174000";

describe("parseFinanceJobProfitabilityFact", () => {
  test("maps a calculated row", () => {
    const fact = parseFinanceJobProfitabilityFact({
      id: FACT_ID, tenant_id: TENANT_ID, job_order_id: JOB_ID, version_number: 1, is_current: true,
      status: "calculated", blocked_reason: null, revenue_basis: "billed",
      revenue_currency: "IDR", revenue_amount: "15000000.00", cost_currency: "IDR", cost_amount: "9000000.00",
      profit_amount: "6000000.00", margin_percent: "40.0000",
      source_invoice_ids: [INVOICE_ID], source_cost_version_ids: [COST_ID],
      recalculation_reason: null, calculated_by_auth_user_id: ACTOR_ID, calculated_at: "2026-07-01T00:00:00.000Z",
      record_version: 1, created_by: "financemanagera", created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
    });
    assert.equal(fact.status, "calculated");
    assert.equal(fact.revenueBasis, "billed");
    assert.equal(fact.revenueAmount, 15000000);
    assert.equal(fact.costAmount, 9000000);
    assert.equal(fact.profitAmount, 6000000);
    assert.equal(fact.marginPercent, 40);
    assert.deepEqual(fact.sourceInvoiceIds, [INVOICE_ID]);
    assert.deepEqual(fact.sourceCostVersionIds, [COST_ID]);
  });

  test("maps an unavailable row with null amounts", () => {
    const fact = parseFinanceJobProfitabilityFact({
      id: FACT_ID, tenant_id: TENANT_ID, job_order_id: JOB_ID, version_number: 1, is_current: true,
      status: "unavailable", blocked_reason: "no_billed_revenue", revenue_basis: "billed",
      revenue_currency: null, revenue_amount: null, cost_currency: null, cost_amount: null,
      profit_amount: null, margin_percent: null,
      source_invoice_ids: [], source_cost_version_ids: [],
      recalculation_reason: null, calculated_by_auth_user_id: ACTOR_ID, calculated_at: "2026-07-01T00:00:00.000Z",
      record_version: 1, created_by: "financemanagera", created_at: "2026-07-01T00:00:00.000Z", updated_at: "2026-07-01T00:00:00.000Z",
    });
    assert.equal(fact.status, "unavailable");
    assert.equal(fact.blockedReason, "no_billed_revenue");
    assert.equal(fact.revenueAmount, null);
    assert.equal(fact.profitAmount, null);
  });
});

describe("parseFinanceProfitabilitySummaryRow", () => {
  test("maps a grouped summary row", () => {
    const row = parseFinanceProfitabilitySummaryRow({
      dimension_key: "acct-1", dimension_label: "Customer One Logistics", currency: "IDR",
      job_count: "2", revenue_amount: "25000000.00", cost_amount: "15000000.00", profit_amount: "10000000.00", margin_percent: "40.0000",
    });
    assert.equal(row.dimensionLabel, "Customer One Logistics");
    assert.equal(row.jobCount, 2);
    assert.equal(row.profitAmount, 10000000);
    assert.equal(row.marginPercent, 40);
  });
});
