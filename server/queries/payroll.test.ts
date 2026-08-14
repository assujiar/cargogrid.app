import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  listPayrollPeriods,
  listPayrollComponents,
  listPayrollEmployeeComponentAssignments,
  listMyPayrollReimbursementRequests,
  listMyPayrollLoans,
  listPayrollRuns,
  listPayrollRunEmployeeResults,
  listMyPayslips,
  getPayslip,
  searchPayrollFinanceHandoffsPendingAcknowledgement,
  getPayrollFinanceHandoffReconciliation,
  PayrollQueryError,
  type PayrollQueryClient,
} from "./payroll.ts";

const TENANT_ID = "123e4567-e89b-12d3-a456-426614174000";
const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ACTOR_ID = "323e4567-e89b-12d3-a456-426614174000";

function fakeClient(response: { data: unknown; error: { message: string } | null }): { client: PayrollQueryClient; calls: { fn: string; args: Record<string, unknown> }[] } {
  const calls: { fn: string; args: Record<string, unknown> }[] = [];
  const client = {
    async rpc(fn: string, args: Record<string, unknown>) {
      calls.push({ fn, args });
      return response;
    },
  } as unknown as PayrollQueryClient;
  return { client, calls };
}

describe("listPayrollPeriods / listPayrollComponents", () => {
  test("listPayrollPeriods defaults limit to 50 and forwards cursor", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPayrollPeriods(client, TENANT_ID, ACTOR_ID, { afterId: ID_1 });
    assert.equal(calls[0]?.fn, "list_payroll_periods");
    assert.equal(calls[0]?.args.p_limit, 50);
    assert.equal(calls[0]?.args.p_after_id, ID_1);
  });

  test("listPayrollComponents surfaces a mapped query error", async () => {
    const { client } = fakeClient({ data: null, error: { message: "insufficient_authority: x" } });
    await assert.rejects(() => listPayrollComponents(client, TENANT_ID, ACTOR_ID), PayrollQueryError);
  });
});

describe("listPayrollEmployeeComponentAssignments / listMyPayrollReimbursementRequests / listMyPayrollLoans", () => {
  test("listPayrollEmployeeComponentAssignments parses amount fields as decimal strings, never JS numbers", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, employee_id: ID_1, component_id: ID_1, override_amount: null, override_percentage: null, manual_amount: "500000.00", currency: "IDR", effective_from: "2026-01-01", effective_to: null, status: "active", record_version: 1 }],
      error: null,
    });
    const rows = await listPayrollEmployeeComponentAssignments(client, TENANT_ID, ID_1, ACTOR_ID);
    assert.equal(typeof rows[0]?.manualAmount, "string");
    assert.equal(rows[0]?.manualAmount, "500000.00");
  });

  test("listMyPayrollReimbursementRequests calls the self-service RPC with no employee_id parameter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyPayrollReimbursementRequests(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_my_payroll_reimbursement_requests");
    assert.equal("p_employee_id" in (calls[0]?.args ?? {}), false);
  });

  test("listMyPayrollLoans calls the self-service RPC", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyPayrollLoans(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_my_payroll_loans");
  });
});

describe("listPayrollRuns / listPayrollRunEmployeeResults", () => {
  test("listPayrollRuns forwards period/status filters", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listPayrollRuns(client, TENANT_ID, ACTOR_ID, { periodId: ID_1, status: "calculated" });
    assert.equal(calls[0]?.args.p_period_id, ID_1);
    assert.equal(calls[0]?.args.p_status, "calculated");
  });

  test("listPayrollRunEmployeeResults parses net_pay as a distinct field", async () => {
    const { client } = fakeClient({
      data: [{ id: ID_1, payroll_run_id: ID_1, employee_id: ID_1, status: "calculated", currency: "IDR", gross_earnings: "5000000.00", total_deductions: "0.00", total_tax: "0.00", total_benefit_employer_cost: "0.00", total_reimbursement: "0.00", total_loan_repayment: "0.00", net_pay: "5000000.00" }],
      error: null,
    });
    const rows = await listPayrollRunEmployeeResults(client, ID_1, ACTOR_ID);
    assert.equal(rows[0]?.netPay, "5000000.00");
  });
});

describe("listMyPayslips / getPayslip", () => {
  test("listMyPayslips calls the self-service RPC with no employee_id parameter", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await listMyPayslips(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "list_my_payslips");
    assert.equal("p_employee_id" in (calls[0]?.args ?? {}), false);
  });

  test("getPayslip parses line_items", async () => {
    const { client } = fakeClient({
      data: {
        id: ID_1, payroll_run_id: ID_1, payroll_period_id: ID_1, employee_id: ID_1, currency: "IDR", gross_earnings: "5000000.00",
        total_deductions: "0.00", total_tax: "0.00", total_benefit_employer_cost: "0.00", total_reimbursement: "0.00",
        total_loan_repayment: "0.00", net_pay: "5000000.00",
        line_items: [{ lineType: "earning", sourceType: "component", description: "base_salary", quantity: null, rate: null, amount: "5000000.00", currency: "IDR" }],
        generated_at: "2026-09-05T00:00:00Z",
      },
      error: null,
    });
    const slip = await getPayslip(client, ID_1, ACTOR_ID);
    assert.equal(slip.lineItems.length, 1);
  });
});

describe("searchPayrollFinanceHandoffsPendingAcknowledgement / getPayrollFinanceHandoffReconciliation", () => {
  test("search calls the Finance-side discovery RPC (mirrors app.search_finance_ap_candidates_for_settlement)", async () => {
    const { client, calls } = fakeClient({ data: [], error: null });
    await searchPayrollFinanceHandoffsPendingAcknowledgement(client, TENANT_ID, ACTOR_ID);
    assert.equal(calls[0]?.fn, "search_payroll_finance_handoffs_pending_acknowledgement");
  });

  test("getPayrollFinanceHandoffReconciliation unwraps a single-row RETURNS TABLE result", async () => {
    const { client } = fakeClient({ data: [{ gl_lines_net: "5000000.00", payment_instructions_total: "5000000.00", run_results_net_total: "5000000.00", is_reconciled: true }], error: null });
    const recon = await getPayrollFinanceHandoffReconciliation(client, ID_1, ACTOR_ID);
    assert.equal(recon.isReconciled, true);
  });
});
