import { test, describe } from "node:test";
import assert from "node:assert/strict";
import {
  parsePayrollPeriodRow,
  parsePayrollComponentRow,
  parsePayrollComponentVersionRow,
  parsePayrollAssignmentRow,
  parsePayrollReimbursementRow,
  parsePayrollLoanRow,
  parsePayrollRunRow,
  parsePayrollRunEmployeeResultRow,
  parsePayrollCalculationLineRow,
  parsePayrollExceptionRow,
  parsePayslipRow,
  parsePayrollFinanceHandoffBatchRow,
  parsePayrollFinanceHandoffReconciliation,
  CreatePayrollComponentVersionInputSchema,
  DecidePayrollReimbursementInputSchema,
  FinalizePayrollRunInputSchema,
  IssuePayrollLoanInputSchema,
} from "./payroll.ts";

const ID_1 = "223e4567-e89b-12d3-a456-426614174000";
const ID_2 = "323e4567-e89b-12d3-a456-426614174000";

describe("parsePayrollPeriodRow", () => {
  test("maps status/frozen_employee_count", () => {
    const r = parsePayrollPeriodRow({
      id: ID_1, code: "pr1-2026-08", period_type: "monthly", period_start: "2026-08-01", period_end: "2026-08-31",
      pay_date: "2026-09-05", status: "input_frozen", frozen_employee_count: 12, record_version: 2,
    });
    assert.equal(r.status, "input_frozen");
    assert.equal(r.frozenEmployeeCount, 12);
  });
});

describe("parsePayrollComponentRow / parsePayrollComponentVersionRow", () => {
  test("platform-wide statutory component carries null tenantId", () => {
    const c = parsePayrollComponentRow({
      id: ID_1, tenant_id: null, code: "pph21", name: "PPh 21", component_type: "tax", is_statutory: true,
      gl_mapping_category: "statutory_tax_payable", status: "active",
    });
    assert.equal(c.tenantId, null);
    assert.equal(c.isStatutory, true);
  });

  test("example-fixture version carries isExampleFixture=true and zero amount", () => {
    const v = parsePayrollComponentVersionRow({
      id: ID_1, component_id: ID_2, version_number: 1, status: "draft", calculation_method: "fixed_amount",
      fixed_amount: "0.00", percentage_rate: null, percentage_of_component_id: null, currency: "IDR",
      effective_from: "2026-01-01", effective_to: null, is_example_fixture: true, sme_evidence_reference: null,
      sme_evidence_date: null, record_version: 1,
    });
    assert.equal(v.isExampleFixture, true);
    assert.equal(v.fixedAmount, "0.00");
    assert.equal(v.smeEvidenceReference, null);
  });

  test("CreatePayrollComponentVersionInputSchema rejects an unknown calculation method", () => {
    assert.throws(() =>
      CreatePayrollComponentVersionInputSchema.parse({
        componentId: ID_1, calculationMethod: "compound_interest", fixedAmount: 10, percentageRate: null,
        percentageOfComponentId: null, currency: "IDR", effectiveFrom: "2026-01-01",
      }),
    );
  });
});

describe("parsePayrollAssignmentRow", () => {
  test("maps override/manual amounts distinctly", () => {
    const a = parsePayrollAssignmentRow({
      id: ID_1, employee_id: ID_2, component_id: ID_1, override_amount: null, override_percentage: null,
      manual_amount: "500000.00", currency: "IDR", effective_from: "2026-01-01", effective_to: null, status: "active",
      record_version: 1,
    });
    assert.equal(a.manualAmount, "500000.00");
    assert.equal(a.overrideAmount, null);
  });
});

describe("parsePayrollReimbursementRow", () => {
  test("maps amount/status", () => {
    const r = parsePayrollReimbursementRow({
      id: ID_1, employee_id: ID_2, category: "travel", amount: "250000.00", currency: "IDR", expense_date: "2026-09-05",
      description: "Client visit taxi", evidence_file_id: null, status: "approved", decided_reason: "looks legit",
      cancel_reason: null, record_version: 3,
    });
    assert.equal(r.amount, "250000.00");
    assert.equal(r.status, "approved");
  });

  test("DecidePayrollReimbursementInputSchema requires a non-empty decidedReason", () => {
    assert.throws(() =>
      DecidePayrollReimbursementInputSchema.parse({ requestId: ID_1, expectedVersion: 1, decision: "approve", decidedReason: "" }),
    );
  });
});

describe("parsePayrollLoanRow", () => {
  test("maps remaining installments distinct from term count", () => {
    const l = parsePayrollLoanRow({
      id: ID_1, employee_id: ID_2, principal_amount: "300000.00", currency: "IDR", installment_amount: "100000.00",
      term_count: 3, remaining_installments: 2, status: "active", is_opening_balance: false, record_version: 2,
    });
    assert.equal(l.termCount, 3);
    assert.equal(l.remainingInstallments, 2);
    assert.notEqual(l.remainingInstallments, l.termCount);
  });

  test("IssuePayrollLoanInputSchema rejects a term over 360", () => {
    assert.throws(() =>
      IssuePayrollLoanInputSchema.parse({
        tenantId: ID_1, employeeId: ID_2, principalAmount: 1000, currency: "IDR", installmentAmount: 10,
        termCount: 361, isOpeningBalance: false, openingRemainingInstallments: null,
      }),
    );
  });
});

describe("parsePayrollRunRow / parsePayrollRunEmployeeResultRow / parsePayrollCalculationLineRow", () => {
  test("run row carries adjustsRunId distinctly from id (correction lineage)", () => {
    const r = parsePayrollRunRow({
      id: ID_1, payroll_period_id: ID_2, run_type: "correction", adjusts_run_id: ID_2, status: "draft",
      currency: "IDR", employee_count: 0, exception_count: 0, approval_request_id: null, record_version: 1,
    });
    assert.equal(r.runType, "correction");
    assert.equal(r.adjustsRunId, ID_2);
  });

  test("employee result net_pay is a distinct field from gross_earnings (decision 10 formula, never conflated)", () => {
    const res = parsePayrollRunEmployeeResultRow({
      id: ID_1, payroll_run_id: ID_2, employee_id: ID_1, status: "calculated", currency: "IDR",
      gross_earnings: "5000000.00", total_deductions: "0.00", total_tax: "0.00", total_benefit_employer_cost: "0.00",
      total_reimbursement: "0.00", total_loan_repayment: "0.00", net_pay: "5000000.00",
    });
    assert.equal(res.grossEarnings, "5000000.00");
    assert.equal(res.netPay, "5000000.00");
  });

  test("calculation line distinguishes source_type from line_type", () => {
    const line = parsePayrollCalculationLineRow({
      id: ID_1, payroll_run_id: ID_2, employee_id: ID_1, source_type: "loan_installment", line_type: "loan_repayment",
      quantity: null, rate: null, amount: "100000.00", currency: "IDR", description: "loan_installment_1",
    });
    assert.equal(line.sourceType, "loan_installment");
    assert.equal(line.lineType, "loan_repayment");
  });
});

describe("parsePayrollExceptionRow", () => {
  test("maps severity/status", () => {
    const e = parsePayrollExceptionRow({
      id: ID_1, payroll_run_id: ID_2, employee_id: ID_1, exception_type: "negative_net_pay", severity: "high",
      message: "computed net pay would be negative", status: "open", resolution_note: null,
    });
    assert.equal(e.severity, "high");
    assert.equal(e.status, "open");
  });
});

describe("parsePayslipRow", () => {
  test("line_items is an array of the explicit allowlisted shape (taxonomy C-07 -- never a whole-row snapshot)", () => {
    const p = parsePayslipRow({
      id: ID_1, payroll_run_id: ID_2, payroll_period_id: ID_1, employee_id: ID_2, currency: "IDR",
      gross_earnings: "5000000.00", total_deductions: "0.00", total_tax: "0.00", total_benefit_employer_cost: "0.00",
      total_reimbursement: "0.00", total_loan_repayment: "0.00", net_pay: "5000000.00",
      line_items: [{ lineType: "earning", sourceType: "component", description: "base_salary", quantity: null, rate: null, amount: "5000000.00", currency: "IDR" }],
      generated_at: "2026-09-05T00:00:00Z",
    });
    assert.equal(p.lineItems.length, 1);
    assert.equal(p.lineItems[0]?.lineType, "earning");
  });
});

describe("parsePayrollFinanceHandoffBatchRow / parsePayrollFinanceHandoffReconciliation", () => {
  test("handoff batch maps totals and status", () => {
    const b = parsePayrollFinanceHandoffBatchRow({
      id: ID_1, payroll_run_id: ID_2, payroll_period_id: ID_1, currency: "IDR", gross_earnings_total: "5000000.00",
      total_deductions_total: "0.00", total_tax_total: "0.00", total_benefit_employer_cost_total: "0.00",
      total_reimbursement_total: "0.00", total_loan_repayment_total: "0.00", net_pay_total: "5000000.00",
      employee_count: 1, status: "pending_acknowledgement", record_version: 1,
    });
    assert.equal(b.status, "pending_acknowledgement");
  });

  test("reconciliation carries isReconciled as a distinct proof field, not merely the totals", () => {
    const r = parsePayrollFinanceHandoffReconciliation({
      gl_lines_net: "5000000.00", payment_instructions_total: "5000000.00", run_results_net_total: "5000000.00", is_reconciled: true,
    });
    assert.equal(r.isReconciled, true);
  });
});

describe("FinalizePayrollRunInputSchema", () => {
  test("decision vocabulary matches PLT-123's own (approved/rejected), not the direct-decide approve/reject shape", () => {
    const parsed = FinalizePayrollRunInputSchema.parse({ requestStepId: ID_1, decision: "approved", reason: "looks good" });
    assert.equal(parsed.decision, "approved");
    assert.throws(() => FinalizePayrollRunInputSchema.parse({ requestStepId: ID_1, decision: "approve", reason: "x" }));
  });
});
