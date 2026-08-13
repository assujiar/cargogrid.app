/**
 * Payroll Foundation, Benefit and Reimbursement contract (HRT-282,
 * CG-S12-HRT-010). Mirrors
 * supabase/migrations/20260731000000_create_hris_payroll_foundation.sql and
 * supabase/migrations/20260731010000_bind_hris_payroll_to_finance_handoff.sql's
 * table shapes and RPCs. Follows the exact directory convention every prior
 * HRT checkpoint established: Zod schemas here, list/read projections in
 * server/queries/payroll.ts, RPC-calling mutation wrappers with an
 * enumerated error-code type in server/mutations/payroll.ts.
 *
 * Every money field is a decimal string on the wire (Postgres numeric ->
 * JS), never coerced to a JS `number` -- this repository's own established
 * "exact decimals, never binary float" discipline (Prompt 282 section 24).
 */

import { z } from "zod";

export const PAYROLL_PERIOD_TYPES = ["monthly", "semi_monthly", "biweekly", "weekly"] as const;
export const PayrollPeriodTypeSchema = z.enum(PAYROLL_PERIOD_TYPES);
export type PayrollPeriodType = z.infer<typeof PayrollPeriodTypeSchema>;

export const PAYROLL_PERIOD_STATUSES = [
  "open", "input_frozen", "calculating", "calculated", "under_review", "pending_approval", "finalized", "cancelled",
] as const;
export const PayrollPeriodStatusSchema = z.enum(PAYROLL_PERIOD_STATUSES);
export type PayrollPeriodStatus = z.infer<typeof PayrollPeriodStatusSchema>;

export const PAYROLL_COMPONENT_TYPES = ["earning", "deduction", "benefit_employer_cost", "tax"] as const;
export const PayrollComponentTypeSchema = z.enum(PAYROLL_COMPONENT_TYPES);
export type PayrollComponentType = z.infer<typeof PayrollComponentTypeSchema>;

export const PAYROLL_COMPONENT_VERSION_STATUSES = ["draft", "approved", "archived"] as const;
export const PayrollComponentVersionStatusSchema = z.enum(PAYROLL_COMPONENT_VERSION_STATUSES);
export type PayrollComponentVersionStatus = z.infer<typeof PayrollComponentVersionStatusSchema>;

export const PAYROLL_CALCULATION_METHODS = ["fixed_amount", "hourly_rate", "percentage_of_component", "manual_per_run"] as const;
export const PayrollCalculationMethodSchema = z.enum(PAYROLL_CALCULATION_METHODS);
export type PayrollCalculationMethod = z.infer<typeof PayrollCalculationMethodSchema>;

export const PAYROLL_ASSIGNMENT_STATUSES = ["active", "ended"] as const;
export const PayrollAssignmentStatusSchema = z.enum(PAYROLL_ASSIGNMENT_STATUSES);
export type PayrollAssignmentStatus = z.infer<typeof PayrollAssignmentStatusSchema>;

export const PAYROLL_REIMBURSEMENT_STATUSES = ["draft", "pending_approval", "approved", "rejected", "cancelled", "paid"] as const;
export const PayrollReimbursementStatusSchema = z.enum(PAYROLL_REIMBURSEMENT_STATUSES);
export type PayrollReimbursementStatus = z.infer<typeof PayrollReimbursementStatusSchema>;

export const PAYROLL_LOAN_STATUSES = ["active", "completed", "cancelled"] as const;
export const PayrollLoanStatusSchema = z.enum(PAYROLL_LOAN_STATUSES);
export type PayrollLoanStatus = z.infer<typeof PayrollLoanStatusSchema>;

export const PAYROLL_RUN_TYPES = ["regular", "off_cycle", "correction", "adjustment"] as const;
export const PayrollRunTypeSchema = z.enum(PAYROLL_RUN_TYPES);
export type PayrollRunType = z.infer<typeof PayrollRunTypeSchema>;

export const PAYROLL_RUN_STATUSES = [
  "draft", "calculating", "calculated", "exception", "pending_approval", "finalized", "cancelled",
] as const;
export const PayrollRunStatusSchema = z.enum(PAYROLL_RUN_STATUSES);
export type PayrollRunStatus = z.infer<typeof PayrollRunStatusSchema>;

export const PAYROLL_EXCEPTION_SEVERITIES = ["low", "medium", "high"] as const;
export const PayrollExceptionSeveritySchema = z.enum(PAYROLL_EXCEPTION_SEVERITIES);
export type PayrollExceptionSeverity = z.infer<typeof PayrollExceptionSeveritySchema>;

export const PAYROLL_EXCEPTION_STATUSES = ["open", "resolved", "waived"] as const;
export const PayrollExceptionStatusSchema = z.enum(PAYROLL_EXCEPTION_STATUSES);
export type PayrollExceptionStatus = z.infer<typeof PayrollExceptionStatusSchema>;

export const PAYROLL_FINANCE_HANDOFF_STATUSES = ["pending_acknowledgement", "acknowledged"] as const;
export const PayrollFinanceHandoffStatusSchema = z.enum(PAYROLL_FINANCE_HANDOFF_STATUSES);
export type PayrollFinanceHandoffStatus = z.infer<typeof PayrollFinanceHandoffStatusSchema>;

const money = z.union([z.string(), z.number()]).transform((v) => String(v));

// --- Core rows ---

export const PayrollPeriodRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  periodType: PayrollPeriodTypeSchema,
  periodStart: z.string(),
  periodEnd: z.string(),
  payDate: z.string(),
  status: PayrollPeriodStatusSchema,
  frozenEmployeeCount: z.number().int().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PayrollPeriodRow = z.infer<typeof PayrollPeriodRowSchema>;

export function parsePayrollPeriodRow(row: Record<string, unknown>): PayrollPeriodRow {
  return PayrollPeriodRowSchema.parse({
    id: row.id,
    code: row.code,
    periodType: row.period_type,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    payDate: row.pay_date,
    status: row.status,
    frozenEmployeeCount: row.frozen_employee_count ?? null,
    recordVersion: row.record_version,
  });
}

export const PayrollComponentRowSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  componentType: PayrollComponentTypeSchema,
  isStatutory: z.boolean(),
  glMappingCategory: z.string(),
  status: z.enum(["active", "archived"]),
});
export type PayrollComponentRow = z.infer<typeof PayrollComponentRowSchema>;

export function parsePayrollComponentRow(row: Record<string, unknown>): PayrollComponentRow {
  return PayrollComponentRowSchema.parse({
    id: row.id,
    tenantId: row.tenant_id ?? null,
    code: row.code,
    name: row.name,
    componentType: row.component_type,
    isStatutory: row.is_statutory,
    glMappingCategory: row.gl_mapping_category,
    status: row.status,
  });
}

export const PayrollComponentVersionRowSchema = z.object({
  id: z.string().uuid(),
  componentId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: PayrollComponentVersionStatusSchema,
  calculationMethod: PayrollCalculationMethodSchema,
  fixedAmount: money.nullable(),
  percentageRate: money.nullable(),
  percentageOfComponentId: z.string().uuid().nullable(),
  currency: z.string(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  isExampleFixture: z.boolean(),
  smeEvidenceReference: z.string().nullable(),
  smeEvidenceDate: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PayrollComponentVersionRow = z.infer<typeof PayrollComponentVersionRowSchema>;

export function parsePayrollComponentVersionRow(row: Record<string, unknown>): PayrollComponentVersionRow {
  return PayrollComponentVersionRowSchema.parse({
    id: row.id,
    componentId: row.component_id,
    versionNumber: row.version_number,
    status: row.status,
    calculationMethod: row.calculation_method,
    fixedAmount: row.fixed_amount ?? null,
    percentageRate: row.percentage_rate ?? null,
    percentageOfComponentId: row.percentage_of_component_id ?? null,
    currency: row.currency,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to ?? null,
    isExampleFixture: row.is_example_fixture,
    smeEvidenceReference: (row.sme_evidence_reference as string | null) ?? null,
    smeEvidenceDate: (row.sme_evidence_date as string | null) ?? null,
    recordVersion: row.record_version,
  });
}

export const PayrollAssignmentRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  componentId: z.string().uuid(),
  overrideAmount: money.nullable(),
  overridePercentage: money.nullable(),
  manualAmount: money.nullable(),
  currency: z.string(),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
  status: PayrollAssignmentStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type PayrollAssignmentRow = z.infer<typeof PayrollAssignmentRowSchema>;

export function parsePayrollAssignmentRow(row: Record<string, unknown>): PayrollAssignmentRow {
  return PayrollAssignmentRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    componentId: row.component_id,
    overrideAmount: row.override_amount ?? null,
    overridePercentage: row.override_percentage ?? null,
    manualAmount: row.manual_amount ?? null,
    currency: row.currency,
    effectiveFrom: row.effective_from,
    effectiveTo: row.effective_to ?? null,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const PayrollReimbursementRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  category: z.string(),
  amount: money,
  currency: z.string(),
  expenseDate: z.string(),
  description: z.string(),
  evidenceFileId: z.string().uuid().nullable(),
  status: PayrollReimbursementStatusSchema,
  decidedReason: z.string().nullable().optional(),
  cancelReason: z.string().nullable().optional(),
  recordVersion: z.number().int().positive(),
});
export type PayrollReimbursementRow = z.infer<typeof PayrollReimbursementRowSchema>;

export function parsePayrollReimbursementRow(row: Record<string, unknown>): PayrollReimbursementRow {
  return PayrollReimbursementRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    category: row.category,
    amount: row.amount,
    currency: row.currency,
    expenseDate: row.expense_date,
    description: row.description,
    evidenceFileId: row.evidence_file_id ?? null,
    status: row.status,
    decidedReason: (row.decided_reason as string | null | undefined) ?? undefined,
    cancelReason: (row.cancel_reason as string | null | undefined) ?? undefined,
    recordVersion: row.record_version,
  });
}

export const PayrollLoanRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  principalAmount: money,
  currency: z.string(),
  installmentAmount: money,
  termCount: z.number().int().positive(),
  remainingInstallments: z.number().int().nonnegative(),
  status: PayrollLoanStatusSchema,
  isOpeningBalance: z.boolean(),
  recordVersion: z.number().int().positive(),
});
export type PayrollLoanRow = z.infer<typeof PayrollLoanRowSchema>;

export function parsePayrollLoanRow(row: Record<string, unknown>): PayrollLoanRow {
  return PayrollLoanRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    principalAmount: row.principal_amount,
    currency: row.currency,
    installmentAmount: row.installment_amount,
    termCount: row.term_count,
    remainingInstallments: row.remaining_installments,
    status: row.status,
    isOpeningBalance: row.is_opening_balance,
    recordVersion: row.record_version,
  });
}

export const PayrollRunRowSchema = z.object({
  id: z.string().uuid(),
  payrollPeriodId: z.string().uuid(),
  runType: PayrollRunTypeSchema,
  adjustsRunId: z.string().uuid().nullable(),
  status: PayrollRunStatusSchema,
  currency: z.string(),
  employeeCount: z.number().int().nonnegative(),
  exceptionCount: z.number().int().nonnegative(),
  approvalRequestId: z.string().uuid().nullable(),
  recordVersion: z.number().int().positive(),
});
export type PayrollRunRow = z.infer<typeof PayrollRunRowSchema>;

export function parsePayrollRunRow(row: Record<string, unknown>): PayrollRunRow {
  return PayrollRunRowSchema.parse({
    id: row.id,
    payrollPeriodId: row.payroll_period_id,
    runType: row.run_type,
    adjustsRunId: row.adjusts_run_id ?? null,
    status: row.status,
    currency: row.currency,
    employeeCount: row.employee_count,
    exceptionCount: row.exception_count,
    approvalRequestId: row.approval_request_id ?? null,
    recordVersion: row.record_version,
  });
}

export const PayrollRunEmployeeResultRowSchema = z.object({
  id: z.string().uuid(),
  payrollRunId: z.string().uuid(),
  employeeId: z.string().uuid(),
  status: z.enum(["calculated", "exception", "reviewed"]),
  currency: z.string(),
  grossEarnings: money,
  totalDeductions: money,
  totalTax: money,
  totalBenefitEmployerCost: money,
  totalReimbursement: money,
  totalLoanRepayment: money,
  netPay: money,
});
export type PayrollRunEmployeeResultRow = z.infer<typeof PayrollRunEmployeeResultRowSchema>;

export function parsePayrollRunEmployeeResultRow(row: Record<string, unknown>): PayrollRunEmployeeResultRow {
  return PayrollRunEmployeeResultRowSchema.parse({
    id: row.id,
    payrollRunId: row.payroll_run_id,
    employeeId: row.employee_id,
    status: row.status,
    currency: row.currency,
    grossEarnings: row.gross_earnings,
    totalDeductions: row.total_deductions,
    totalTax: row.total_tax,
    totalBenefitEmployerCost: row.total_benefit_employer_cost,
    totalReimbursement: row.total_reimbursement,
    totalLoanRepayment: row.total_loan_repayment,
    netPay: row.net_pay,
  });
}

export const PayrollCalculationLineRowSchema = z.object({
  id: z.string().uuid(),
  payrollRunId: z.string().uuid(),
  employeeId: z.string().uuid(),
  sourceType: z.enum(["component", "loan_installment", "reimbursement"]),
  lineType: z.enum(["earning", "deduction", "benefit_employer_cost", "tax", "loan_repayment", "reimbursement"]),
  quantity: money.nullable(),
  rate: money.nullable(),
  amount: money,
  currency: z.string(),
  description: z.string().nullable(),
});
export type PayrollCalculationLineRow = z.infer<typeof PayrollCalculationLineRowSchema>;

export function parsePayrollCalculationLineRow(row: Record<string, unknown>): PayrollCalculationLineRow {
  return PayrollCalculationLineRowSchema.parse({
    id: row.id,
    payrollRunId: row.payroll_run_id,
    employeeId: row.employee_id,
    sourceType: row.source_type,
    lineType: row.line_type,
    quantity: row.quantity ?? null,
    rate: row.rate ?? null,
    amount: row.amount,
    currency: row.currency,
    description: (row.description as string | null) ?? null,
  });
}

export const PayrollExceptionRowSchema = z.object({
  id: z.string().uuid(),
  payrollRunId: z.string().uuid(),
  employeeId: z.string().uuid().nullable(),
  exceptionType: z.string(),
  severity: PayrollExceptionSeveritySchema,
  message: z.string(),
  status: PayrollExceptionStatusSchema,
  resolutionNote: z.string().nullable().optional(),
});
export type PayrollExceptionRow = z.infer<typeof PayrollExceptionRowSchema>;

export function parsePayrollExceptionRow(row: Record<string, unknown>): PayrollExceptionRow {
  return PayrollExceptionRowSchema.parse({
    id: row.id,
    payrollRunId: row.payroll_run_id,
    employeeId: row.employee_id ?? null,
    exceptionType: row.exception_type,
    severity: row.severity,
    message: row.message,
    status: row.status,
    resolutionNote: (row.resolution_note as string | null | undefined) ?? undefined,
  });
}

export const PayslipLineItemSchema = z.object({
  lineType: z.string(),
  sourceType: z.string(),
  description: z.string().nullable(),
  quantity: money.nullable(),
  rate: money.nullable(),
  amount: money,
  currency: z.string(),
});
export type PayslipLineItem = z.infer<typeof PayslipLineItemSchema>;

export const PayslipRowSchema = z.object({
  id: z.string().uuid(),
  payrollRunId: z.string().uuid(),
  payrollPeriodId: z.string().uuid(),
  employeeId: z.string().uuid(),
  currency: z.string(),
  grossEarnings: money,
  totalDeductions: money,
  totalTax: money,
  totalBenefitEmployerCost: money,
  totalReimbursement: money,
  totalLoanRepayment: money,
  netPay: money,
  lineItems: z.array(PayslipLineItemSchema),
  generatedAt: z.string(),
});
export type PayslipRow = z.infer<typeof PayslipRowSchema>;

export function parsePayslipRow(row: Record<string, unknown>): PayslipRow {
  return PayslipRowSchema.parse({
    id: row.id,
    payrollRunId: row.payroll_run_id,
    payrollPeriodId: row.payroll_period_id,
    employeeId: row.employee_id,
    currency: row.currency,
    grossEarnings: row.gross_earnings,
    totalDeductions: row.total_deductions,
    totalTax: row.total_tax,
    totalBenefitEmployerCost: row.total_benefit_employer_cost,
    totalReimbursement: row.total_reimbursement,
    totalLoanRepayment: row.total_loan_repayment,
    netPay: row.net_pay,
    lineItems: row.line_items,
    generatedAt: row.generated_at,
  });
}

export const PayrollFinanceHandoffBatchRowSchema = z.object({
  id: z.string().uuid(),
  payrollRunId: z.string().uuid(),
  payrollPeriodId: z.string().uuid(),
  currency: z.string(),
  grossEarningsTotal: money,
  totalDeductionsTotal: money,
  totalTaxTotal: money,
  totalBenefitEmployerCostTotal: money,
  totalReimbursementTotal: money,
  totalLoanRepaymentTotal: money,
  netPayTotal: money,
  employeeCount: z.number().int().nonnegative(),
  status: PayrollFinanceHandoffStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type PayrollFinanceHandoffBatchRow = z.infer<typeof PayrollFinanceHandoffBatchRowSchema>;

export function parsePayrollFinanceHandoffBatchRow(row: Record<string, unknown>): PayrollFinanceHandoffBatchRow {
  return PayrollFinanceHandoffBatchRowSchema.parse({
    id: row.id,
    payrollRunId: row.payroll_run_id,
    payrollPeriodId: row.payroll_period_id,
    currency: row.currency,
    grossEarningsTotal: row.gross_earnings_total,
    totalDeductionsTotal: row.total_deductions_total,
    totalTaxTotal: row.total_tax_total,
    totalBenefitEmployerCostTotal: row.total_benefit_employer_cost_total,
    totalReimbursementTotal: row.total_reimbursement_total,
    totalLoanRepaymentTotal: row.total_loan_repayment_total,
    netPayTotal: row.net_pay_total,
    employeeCount: row.employee_count,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const PayrollFinanceHandoffReconciliationSchema = z.object({
  glLinesNet: money,
  paymentInstructionsTotal: money,
  runResultsNetTotal: money,
  isReconciled: z.boolean(),
});
export type PayrollFinanceHandoffReconciliation = z.infer<typeof PayrollFinanceHandoffReconciliationSchema>;

export function parsePayrollFinanceHandoffReconciliation(row: Record<string, unknown>): PayrollFinanceHandoffReconciliation {
  return PayrollFinanceHandoffReconciliationSchema.parse({
    glLinesNet: row.gl_lines_net,
    paymentInstructionsTotal: row.payment_instructions_total,
    runResultsNetTotal: row.run_results_net_total,
    isReconciled: row.is_reconciled,
  });
}

// --- Mutation inputs ---

export const CreatePayrollPeriodInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  code: z.string().min(2).max(60),
  periodType: PayrollPeriodTypeSchema,
  periodStart: z.string(),
  periodEnd: z.string(),
  payDate: z.string(),
});
export type CreatePayrollPeriodInput = z.infer<typeof CreatePayrollPeriodInputSchema>;

export const FreezePayrollPeriodInputsInputSchema = z.object({ periodId: z.string().uuid(), expectedVersion: z.number().int().positive() });
export type FreezePayrollPeriodInputsInput = z.infer<typeof FreezePayrollPeriodInputsInputSchema>;

export const ReopenPayrollPeriodInputsInputSchema = z.object({ periodId: z.string().uuid(), expectedVersion: z.number().int().positive(), reason: z.string().min(1) });
export type ReopenPayrollPeriodInputsInput = z.infer<typeof ReopenPayrollPeriodInputsInputSchema>;

export const CreatePayrollComponentInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(2).max(60),
  name: z.string().min(1),
  componentType: PayrollComponentTypeSchema,
  glMappingCategory: z.string().min(1),
});
export type CreatePayrollComponentInput = z.infer<typeof CreatePayrollComponentInputSchema>;

export const CreatePayrollComponentVersionInputSchema = z.object({
  componentId: z.string().uuid(),
  calculationMethod: PayrollCalculationMethodSchema,
  fixedAmount: z.number().nonnegative().nullable(),
  percentageRate: z.number().nonnegative().nullable(),
  percentageOfComponentId: z.string().uuid().nullable(),
  currency: z.string().min(1),
  effectiveFrom: z.string(),
});
export type CreatePayrollComponentVersionInput = z.infer<typeof CreatePayrollComponentVersionInputSchema>;

export const AttachPayrollComponentVersionEvidenceInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  smeEvidenceReference: z.string().min(1),
  smeEvidenceDate: z.string(),
  smeEvidenceNote: z.string().nullable().optional(),
});
export type AttachPayrollComponentVersionEvidenceInput = z.infer<typeof AttachPayrollComponentVersionEvidenceInputSchema>;

export const ApprovePayrollComponentVersionInputSchema = z.object({ versionId: z.string().uuid(), expectedVersion: z.number().int().positive() });
export type ApprovePayrollComponentVersionInput = z.infer<typeof ApprovePayrollComponentVersionInputSchema>;

export const ArchivePayrollComponentVersionInputSchema = z.object({ versionId: z.string().uuid(), expectedVersion: z.number().int().positive() });
export type ArchivePayrollComponentVersionInput = z.infer<typeof ArchivePayrollComponentVersionInputSchema>;

export const AssignPayrollComponentInputSchema = z.object({
  tenantId: z.string().uuid(),
  employeeId: z.string().uuid(),
  componentId: z.string().uuid(),
  overrideAmount: z.number().nonnegative().nullable(),
  overridePercentage: z.number().nonnegative().nullable(),
  manualAmount: z.number().nonnegative().nullable(),
  currency: z.string().min(1),
  effectiveFrom: z.string(),
  effectiveTo: z.string().nullable(),
});
export type AssignPayrollComponentInput = z.infer<typeof AssignPayrollComponentInputSchema>;

export const EndPayrollComponentAssignmentInputSchema = z.object({
  assignmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  effectiveTo: z.string().nullable(),
  endReason: z.string().min(1),
});
export type EndPayrollComponentAssignmentInput = z.infer<typeof EndPayrollComponentAssignmentInputSchema>;

export const CreatePayrollReimbursementInputSchema = z.object({
  tenantId: z.string().uuid(),
  category: z.string().min(2).max(60),
  amount: z.number().positive(),
  currency: z.string().min(1),
  expenseDate: z.string(),
  description: z.string().min(1),
  evidenceFileId: z.string().uuid().nullable(),
  idempotencyKey: z.string().nullable().optional(),
});
export type CreatePayrollReimbursementInput = z.infer<typeof CreatePayrollReimbursementInputSchema>;

export const CreatePayrollReimbursementForEmployeeInputSchema = CreatePayrollReimbursementInputSchema.extend({ employeeId: z.string().uuid() });
export type CreatePayrollReimbursementForEmployeeInput = z.infer<typeof CreatePayrollReimbursementForEmployeeInputSchema>;

export const SubmitPayrollReimbursementInputSchema = z.object({ requestId: z.string().uuid(), expectedVersion: z.number().int().positive() });
export type SubmitPayrollReimbursementInput = z.infer<typeof SubmitPayrollReimbursementInputSchema>;

export const DecidePayrollReimbursementInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["approve", "reject"]),
  decidedReason: z.string().min(1),
});
export type DecidePayrollReimbursementInput = z.infer<typeof DecidePayrollReimbursementInputSchema>;

export const CancelPayrollReimbursementInputSchema = z.object({ requestId: z.string().uuid(), expectedVersion: z.number().int().positive(), reason: z.string().min(1) });
export type CancelPayrollReimbursementInput = z.infer<typeof CancelPayrollReimbursementInputSchema>;

export const IssuePayrollLoanInputSchema = z.object({
  tenantId: z.string().uuid(),
  employeeId: z.string().uuid(),
  principalAmount: z.number().positive(),
  currency: z.string().min(1),
  installmentAmount: z.number().positive(),
  termCount: z.number().int().positive().max(360),
  isOpeningBalance: z.boolean().default(false),
  openingRemainingInstallments: z.number().int().nonnegative().nullable(),
  notes: z.string().nullable().optional(),
});
export type IssuePayrollLoanInput = z.infer<typeof IssuePayrollLoanInputSchema>;

export const CancelPayrollLoanInputSchema = z.object({ loanId: z.string().uuid(), expectedVersion: z.number().int().positive(), reason: z.string().min(1) });
export type CancelPayrollLoanInput = z.infer<typeof CancelPayrollLoanInputSchema>;

export const CreatePayrollRunInputSchema = z.object({
  tenantId: z.string().uuid(),
  periodId: z.string().uuid(),
  runType: PayrollRunTypeSchema,
  adjustsRunId: z.string().uuid().nullable(),
  currency: z.string().min(1),
  idempotencyKey: z.string().nullable().optional(),
});
export type CreatePayrollRunInput = z.infer<typeof CreatePayrollRunInputSchema>;

export const CalculatePayrollRunInputSchema = z.object({ runId: z.string().uuid(), expectedVersion: z.number().int().positive(), idempotencyKey: z.string().nullable().optional() });
export type CalculatePayrollRunInput = z.infer<typeof CalculatePayrollRunInputSchema>;

export const ResolvePayrollExceptionInputSchema = z.object({ exceptionId: z.string().uuid(), resolutionNote: z.string().min(1) });
export type ResolvePayrollExceptionInput = z.infer<typeof ResolvePayrollExceptionInputSchema>;

export const WaivePayrollExceptionInputSchema = z.object({ exceptionId: z.string().uuid(), resolutionNote: z.string().min(1) });
export type WaivePayrollExceptionInput = z.infer<typeof WaivePayrollExceptionInputSchema>;

export const SubmitPayrollRunForFinalizationInputSchema = z.object({ runId: z.string().uuid(), expectedVersion: z.number().int().positive() });
export type SubmitPayrollRunForFinalizationInput = z.infer<typeof SubmitPayrollRunForFinalizationInputSchema>;

export const FinalizePayrollRunInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: z.enum(["approved", "rejected"]),
  reason: z.string().min(1),
});
export type FinalizePayrollRunInput = z.infer<typeof FinalizePayrollRunInputSchema>;

export const CancelPayrollRunInputSchema = z.object({ runId: z.string().uuid(), expectedVersion: z.number().int().positive(), reason: z.string().min(1) });
export type CancelPayrollRunInput = z.infer<typeof CancelPayrollRunInputSchema>;

export const PrepareFinancePayrollHandoffInputSchema = z.object({ tenantId: z.string().uuid(), runId: z.string().uuid() });
export type PrepareFinancePayrollHandoffInput = z.infer<typeof PrepareFinancePayrollHandoffInputSchema>;

export const AcknowledgePayrollFinanceHandoffInputSchema = z.object({ batchId: z.string().uuid(), expectedVersion: z.number().int().positive() });
export type AcknowledgePayrollFinanceHandoffInput = z.infer<typeof AcknowledgePayrollFinanceHandoffInputSchema>;
