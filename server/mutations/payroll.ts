/**
 * Payroll Foundation, Benefit and Reimbursement mutation primitives
 * (HRT-282, CG-S12-HRT-010). Thin, typed wrappers around every write RPC in
 * supabase/migrations/20260731000000_create_hris_payroll_foundation.sql
 * and supabase/migrations/20260731010000_bind_hris_payroll_to_finance_handoff.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parsePayrollPeriodRow,
  parsePayrollComponentRow,
  parsePayrollComponentVersionRow,
  parsePayrollAssignmentRow,
  parsePayrollReimbursementRow,
  parsePayrollLoanRow,
  parsePayrollRunRow,
  parsePayrollExceptionRow,
  parsePayrollFinanceHandoffBatchRow,
  type PayrollPeriodRow,
  type PayrollComponentRow,
  type PayrollComponentVersionRow,
  type PayrollAssignmentRow,
  type PayrollReimbursementRow,
  type PayrollLoanRow,
  type PayrollRunRow,
  type PayrollExceptionRow,
  type PayrollFinanceHandoffBatchRow,
} from "../contracts/payroll/payroll.ts";

export type PayrollMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const PAYROLL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority", "insufficient_privilege",
  "payroll_period_not_found", "invalid_transition", "stale_version", "reason_required",
  "payroll_period_has_advanced_run",
  "payroll_component_not_found", "invalid_component_type", "invalid_calculation_method",
  "payroll_component_version_not_found", "payroll_component_version_not_draft",
  "payroll_component_version_example_fixture_not_activatable", "sme_evidence_missing",
  "payroll_component_version_overlap",
  "employee_not_found", "employee_not_active", "payroll_assignment_not_found", "payroll_assignment_overlap",
  "invalid_amount", "description_required", "evidence_file_not_found", "evidence_file_not_clean",
  "idempotency_key_conflict",
  "payroll_reimbursement_request_not_found", "self_approval_not_permitted", "invalid_decision",
  "invalid_loan_terms", "invalid_opening_remaining_installments", "payroll_loan_not_found",
  "payroll_run_not_found", "invalid_run_type", "adjusts_run_id_required", "payroll_run_adjust_target_not_finalized",
  "payroll_run_already_active", "payroll_period_inputs_not_frozen",
  "payroll_exception_not_found", "payroll_run_has_open_exceptions",
  "approval_definition_not_configured", "approval_step_not_found", "not_a_payroll_run_approval",
  "approval_invalid_decision", "approval_self_approval_denied", "approval_request_not_pending",
  "payroll_finance_handoff_batch_not_found", "payroll_run_not_finalized",
] as const;
export type PayrollKnownMutationErrorCode = (typeof PAYROLL_KNOWN_MUTATION_ERROR_CODES)[number];

export class PayrollMutationError extends Error {
  readonly code: PayrollKnownMutationErrorCode | "unknown";
  constructor(message: string) {
    super(message);
    this.name = "PayrollMutationError";
    const prefix = message.split(":")[0]?.trim() ?? "";
    this.code = (PAYROLL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)
      ? (prefix as PayrollKnownMutationErrorCode)
      : "unknown";
  }
}

function unwrap<T>(data: T, error: { message: string } | null): T {
  if (error) throw new PayrollMutationError(error.message);
  return data;
}

// --- Period ---

export async function createPayrollPeriod(
  client: PayrollMutationRpcClient,
  input: { tenantId: string; orgUnitId: string | null; code: string; periodType: string; periodStart: string; periodEnd: string; payDate: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollPeriodRow> {
  const { data, error } = await client.rpc("create_payroll_period", {
    p_tenant_id: input.tenantId, p_org_unit_id: input.orgUnitId, p_code: input.code, p_period_type: input.periodType,
    p_period_start: input.periodStart, p_period_end: input.periodEnd, p_pay_date: input.payDate,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollPeriodRow(unwrap(data, error) as Record<string, unknown>);
}

export async function freezePayrollPeriodInputs(
  client: PayrollMutationRpcClient, input: { periodId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollPeriodRow> {
  const { data, error } = await client.rpc("freeze_payroll_period_inputs", {
    p_period_id: input.periodId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollPeriodRow(unwrap(data, error) as Record<string, unknown>);
}

export async function reopenPayrollPeriodInputs(
  client: PayrollMutationRpcClient, input: { periodId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollPeriodRow> {
  const { data, error } = await client.rpc("reopen_payroll_period_inputs", {
    p_period_id: input.periodId, p_expected_version: input.expectedVersion, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollPeriodRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Components ---

export async function createPayrollComponent(
  client: PayrollMutationRpcClient,
  input: { tenantId: string; code: string; name: string; componentType: string; glMappingCategory: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollComponentRow> {
  const { data, error } = await client.rpc("create_payroll_component", {
    p_tenant_id: input.tenantId, p_code: input.code, p_name: input.name, p_component_type: input.componentType,
    p_gl_mapping_category: input.glMappingCategory, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollComponentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function createPayrollComponentVersion(
  client: PayrollMutationRpcClient,
  input: {
    componentId: string; calculationMethod: string; fixedAmount: number | null; percentageRate: number | null;
    percentageOfComponentId: string | null; currency: string; effectiveFrom: string; actorAuthUserId: string; actorLabel: string;
  },
): Promise<PayrollComponentVersionRow> {
  const { data, error } = await client.rpc("create_payroll_component_version", {
    p_component_id: input.componentId, p_calculation_method: input.calculationMethod, p_fixed_amount: input.fixedAmount,
    p_percentage_rate: input.percentageRate, p_percentage_of_component_id: input.percentageOfComponentId,
    p_currency: input.currency, p_effective_from: input.effectiveFrom, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollComponentVersionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function attachPayrollComponentVersionEvidence(
  client: PayrollMutationRpcClient,
  input: { versionId: string; expectedVersion: number; smeEvidenceReference: string; smeEvidenceDate: string; smeEvidenceNote: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollComponentVersionRow> {
  const { data, error } = await client.rpc("attach_payroll_component_version_evidence", {
    p_version_id: input.versionId, p_expected_version: input.expectedVersion, p_sme_evidence_reference: input.smeEvidenceReference,
    p_sme_evidence_date: input.smeEvidenceDate, p_sme_evidence_note: input.smeEvidenceNote,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollComponentVersionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function approvePayrollComponentVersion(
  client: PayrollMutationRpcClient, input: { versionId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollComponentVersionRow> {
  const { data, error } = await client.rpc("approve_payroll_component_version", {
    p_version_id: input.versionId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollComponentVersionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function archivePayrollComponentVersion(
  client: PayrollMutationRpcClient, input: { versionId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollComponentVersionRow> {
  const { data, error } = await client.rpc("archive_payroll_component_version", {
    p_version_id: input.versionId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollComponentVersionRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Employee component assignment ---

export async function assignPayrollComponentToEmployee(
  client: PayrollMutationRpcClient,
  input: {
    tenantId: string; employeeId: string; componentId: string; overrideAmount: number | null; overridePercentage: number | null;
    manualAmount: number | null; currency: string; effectiveFrom: string; effectiveTo: string | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<PayrollAssignmentRow> {
  const { data, error } = await client.rpc("assign_payroll_component_to_employee", {
    p_tenant_id: input.tenantId, p_employee_id: input.employeeId, p_component_id: input.componentId,
    p_override_amount: input.overrideAmount, p_override_percentage: input.overridePercentage, p_manual_amount: input.manualAmount,
    p_currency: input.currency, p_effective_from: input.effectiveFrom, p_effective_to: input.effectiveTo,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

export async function endPayrollComponentAssignment(
  client: PayrollMutationRpcClient,
  input: { assignmentId: string; expectedVersion: number; effectiveTo: string | null; endReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollAssignmentRow> {
  const { data, error } = await client.rpc("end_payroll_component_assignment", {
    p_assignment_id: input.assignmentId, p_expected_version: input.expectedVersion, p_effective_to: input.effectiveTo,
    p_end_reason: input.endReason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollAssignmentRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Reimbursement ---

export async function createPayrollReimbursementRequest(
  client: PayrollMutationRpcClient,
  input: {
    tenantId: string; category: string; amount: number; currency: string; expenseDate: string; description: string;
    evidenceFileId: string | null; idempotencyKey: string | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<PayrollReimbursementRow> {
  const { data, error } = await client.rpc("create_payroll_reimbursement_request", {
    p_tenant_id: input.tenantId, p_category: input.category, p_amount: input.amount, p_currency: input.currency,
    p_expense_date: input.expenseDate, p_description: input.description, p_evidence_file_id: input.evidenceFileId,
    p_idempotency_key: input.idempotencyKey, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollReimbursementRow(unwrap(data, error) as Record<string, unknown>);
}

export async function createPayrollReimbursementRequestForEmployee(
  client: PayrollMutationRpcClient,
  input: {
    tenantId: string; employeeId: string; category: string; amount: number; currency: string; expenseDate: string; description: string;
    evidenceFileId: string | null; idempotencyKey: string | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<PayrollReimbursementRow> {
  const { data, error } = await client.rpc("create_payroll_reimbursement_request_for_employee", {
    p_tenant_id: input.tenantId, p_employee_id: input.employeeId, p_category: input.category, p_amount: input.amount,
    p_currency: input.currency, p_expense_date: input.expenseDate, p_description: input.description,
    p_evidence_file_id: input.evidenceFileId, p_idempotency_key: input.idempotencyKey,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollReimbursementRow(unwrap(data, error) as Record<string, unknown>);
}

export async function submitPayrollReimbursementRequest(
  client: PayrollMutationRpcClient, input: { requestId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollReimbursementRow> {
  const { data, error } = await client.rpc("submit_payroll_reimbursement_request", {
    p_request_id: input.requestId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollReimbursementRow(unwrap(data, error) as Record<string, unknown>);
}

export async function decidePayrollReimbursementRequest(
  client: PayrollMutationRpcClient,
  input: { requestId: string; expectedVersion: number; decision: "approve" | "reject"; decidedReason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollReimbursementRow> {
  const { data, error } = await client.rpc("decide_payroll_reimbursement_request", {
    p_request_id: input.requestId, p_expected_version: input.expectedVersion, p_decision: input.decision,
    p_decided_reason: input.decidedReason, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollReimbursementRow(unwrap(data, error) as Record<string, unknown>);
}

export async function cancelPayrollReimbursementRequest(
  client: PayrollMutationRpcClient, input: { requestId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollReimbursementRow> {
  const { data, error } = await client.rpc("cancel_payroll_reimbursement_request", {
    p_request_id: input.requestId, p_expected_version: input.expectedVersion, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollReimbursementRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Loan ---

export async function issuePayrollLoan(
  client: PayrollMutationRpcClient,
  input: {
    tenantId: string; employeeId: string; principalAmount: number; currency: string; installmentAmount: number; termCount: number;
    isOpeningBalance: boolean; openingRemainingInstallments: number | null; notes: string | null; actorAuthUserId: string; actorLabel: string;
  },
): Promise<PayrollLoanRow> {
  const { data, error } = await client.rpc("issue_payroll_loan", {
    p_tenant_id: input.tenantId, p_employee_id: input.employeeId, p_principal_amount: input.principalAmount, p_currency: input.currency,
    p_installment_amount: input.installmentAmount, p_term_count: input.termCount, p_is_opening_balance: input.isOpeningBalance,
    p_opening_remaining_installments: input.openingRemainingInstallments, p_notes: input.notes,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollLoanRow(unwrap(data, error) as Record<string, unknown>);
}

export async function cancelPayrollLoan(
  client: PayrollMutationRpcClient, input: { loanId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollLoanRow> {
  const { data, error } = await client.rpc("cancel_payroll_loan", {
    p_loan_id: input.loanId, p_expected_version: input.expectedVersion, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollLoanRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Run lifecycle ---

export async function createPayrollRun(
  client: PayrollMutationRpcClient,
  input: { tenantId: string; periodId: string; runType: string; adjustsRunId: string | null; currency: string; idempotencyKey: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollRunRow> {
  const { data, error } = await client.rpc("create_payroll_run", {
    p_tenant_id: input.tenantId, p_period_id: input.periodId, p_run_type: input.runType, p_adjusts_run_id: input.adjustsRunId,
    p_currency: input.currency, p_idempotency_key: input.idempotencyKey, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollRunRow(unwrap(data, error) as Record<string, unknown>);
}

export async function calculatePayrollRun(
  client: PayrollMutationRpcClient, input: { runId: string; expectedVersion: number; idempotencyKey: string | null; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollRunRow> {
  const { data, error } = await client.rpc("calculate_payroll_run", {
    p_run_id: input.runId, p_expected_version: input.expectedVersion, p_idempotency_key: input.idempotencyKey,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollRunRow(unwrap(data, error) as Record<string, unknown>);
}

export async function resolvePayrollException(
  client: PayrollMutationRpcClient, input: { exceptionId: string; resolutionNote: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollExceptionRow> {
  const { data, error } = await client.rpc("resolve_payroll_exception", {
    p_exception_id: input.exceptionId, p_resolution_note: input.resolutionNote, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollExceptionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function waivePayrollException(
  client: PayrollMutationRpcClient, input: { exceptionId: string; resolutionNote: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollExceptionRow> {
  const { data, error } = await client.rpc("waive_payroll_exception", {
    p_exception_id: input.exceptionId, p_resolution_note: input.resolutionNote, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollExceptionRow(unwrap(data, error) as Record<string, unknown>);
}

export async function submitPayrollRunForFinalization(
  client: PayrollMutationRpcClient, input: { runId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollRunRow> {
  const { data, error } = await client.rpc("submit_payroll_run_for_finalization", {
    p_run_id: input.runId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollRunRow(unwrap(data, error) as Record<string, unknown>);
}

export async function finalizePayrollRun(
  client: PayrollMutationRpcClient,
  input: { requestStepId: string; decision: "approved" | "rejected"; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollRunRow> {
  const { data, error } = await client.rpc("finalize_payroll_run", {
    p_request_step_id: input.requestStepId, p_decision: input.decision, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollRunRow(unwrap(data, error) as Record<string, unknown>);
}

export async function cancelPayrollRun(
  client: PayrollMutationRpcClient, input: { runId: string; expectedVersion: number; reason: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollRunRow> {
  const { data, error } = await client.rpc("cancel_payroll_run", {
    p_run_id: input.runId, p_expected_version: input.expectedVersion, p_reason: input.reason,
    p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollRunRow(unwrap(data, error) as Record<string, unknown>);
}

// --- Finance handoff ---

export async function prepareFinancePayrollDisbursementHandoffFromPayrollRun(
  client: PayrollMutationRpcClient, input: { tenantId: string; runId: string; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollFinanceHandoffBatchRow> {
  const { data, error } = await client.rpc("prepare_finance_payroll_disbursement_handoff_from_payroll_run", {
    p_tenant_id: input.tenantId, p_run_id: input.runId, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollFinanceHandoffBatchRow(unwrap(data, error) as Record<string, unknown>);
}

export async function acknowledgePayrollFinanceHandoffBatch(
  client: PayrollMutationRpcClient, input: { batchId: string; expectedVersion: number; actorAuthUserId: string; actorLabel: string },
): Promise<PayrollFinanceHandoffBatchRow> {
  const { data, error } = await client.rpc("acknowledge_payroll_finance_handoff_batch", {
    p_batch_id: input.batchId, p_expected_version: input.expectedVersion, p_actor_auth_user_id: input.actorAuthUserId, p_actor_label: input.actorLabel,
  });
  return parsePayrollFinanceHandoffBatchRow(unwrap(data, error) as Record<string, unknown>);
}
