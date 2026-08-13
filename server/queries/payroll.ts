/**
 * Payroll Foundation, Benefit and Reimbursement read queries (HRT-282,
 * CG-S12-HRT-010). Thin, typed wrappers around every read RPC in
 * supabase/migrations/20260731000000_create_hris_payroll_foundation.sql
 * and supabase/migrations/20260731010000_bind_hris_payroll_to_finance_handoff.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { listPendingApprovalStepsForActor, type ApprovalQueryRpcClient } from "./approval.ts";
import type { ApprovalRequestStep } from "../contracts/approval/approval.ts";
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
  type PayrollPeriodRow,
  type PayrollComponentRow,
  type PayrollComponentVersionRow,
  type PayrollAssignmentRow,
  type PayrollReimbursementRow,
  type PayrollLoanRow,
  type PayrollRunRow,
  type PayrollRunEmployeeResultRow,
  type PayrollCalculationLineRow,
  type PayrollExceptionRow,
  type PayslipRow,
  type PayrollFinanceHandoffBatchRow,
  type PayrollFinanceHandoffReconciliation,
} from "../contracts/payroll/payroll.ts";

export type PayrollQueryClient = Pick<SupabaseClient, "rpc">;

export class PayrollQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PayrollQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

function toApprovalQueryRpcClient(client: PayrollQueryClient): ApprovalQueryRpcClient {
  return { rpc: async (fn, args) => await client.rpc(fn, args) };
}

/**
 * Composes with server/queries/approval.ts's own listPendingApprovalStepsForActor
 * (PLT-123 is the single approval-inbox source of truth, never a bespoke payroll-
 * specific inbox), mirroring server/queries/leave.ts's/credit.ts's established
 * composition shape exactly.
 */
export async function listMyPendingPayrollApprovalSteps(client: PayrollQueryClient, tenantId: string, actorAuthUserId: string): Promise<ApprovalRequestStep[]> {
  return listPendingApprovalStepsForActor(toApprovalQueryRpcClient(client), { tenantId, actorAuthUserId });
}

export async function listPayrollPeriods(
  client: PayrollQueryClient, tenantId: string, actorAuthUserId: string,
  options?: { status?: string | null; limit?: number; afterId?: string | null },
): Promise<PayrollPeriodRow[]> {
  const { data, error } = await client.rpc("list_payroll_periods", {
    p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50, p_after_id: options?.afterId ?? null,
  });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollPeriodRow);
}

export async function getPayrollPeriod(client: PayrollQueryClient, periodId: string, actorAuthUserId: string): Promise<PayrollPeriodRow> {
  const { data, error } = await client.rpc("get_payroll_period", { p_period_id: periodId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return parsePayrollPeriodRow(data as Record<string, unknown>);
}

export async function listPayrollComponents(client: PayrollQueryClient, tenantId: string, actorAuthUserId: string): Promise<PayrollComponentRow[]> {
  const { data, error } = await client.rpc("list_payroll_components", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollComponentRow);
}

export async function listPayrollComponentVersions(client: PayrollQueryClient, componentId: string, actorAuthUserId: string): Promise<PayrollComponentVersionRow[]> {
  const { data, error } = await client.rpc("list_payroll_component_versions", { p_component_id: componentId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollComponentVersionRow);
}

export async function listPayrollEmployeeComponentAssignments(
  client: PayrollQueryClient, tenantId: string, employeeId: string, actorAuthUserId: string,
): Promise<PayrollAssignmentRow[]> {
  const { data, error } = await client.rpc("list_payroll_employee_component_assignments", {
    p_tenant_id: tenantId, p_employee_id: employeeId, p_actor_auth_user_id: actorAuthUserId,
  });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollAssignmentRow);
}

export async function listMyPayrollReimbursementRequests(client: PayrollQueryClient, tenantId: string, actorAuthUserId: string): Promise<PayrollReimbursementRow[]> {
  const { data, error } = await client.rpc("list_my_payroll_reimbursement_requests", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollReimbursementRow);
}

export async function listPayrollReimbursementRequests(
  client: PayrollQueryClient, tenantId: string, actorAuthUserId: string,
  options?: { employeeId?: string | null; status?: string | null; limit?: number; afterId?: string | null },
): Promise<PayrollReimbursementRow[]> {
  const { data, error } = await client.rpc("list_payroll_reimbursement_requests", {
    p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: options?.employeeId ?? null,
    p_status: options?.status ?? null, p_limit: options?.limit ?? 50, p_after_id: options?.afterId ?? null,
  });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollReimbursementRow);
}

export async function listMyPayrollLoans(client: PayrollQueryClient, tenantId: string, actorAuthUserId: string): Promise<PayrollLoanRow[]> {
  const { data, error } = await client.rpc("list_my_payroll_loans", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollLoanRow);
}

export async function listPayrollLoans(
  client: PayrollQueryClient, tenantId: string, actorAuthUserId: string, options?: { employeeId?: string | null; status?: string | null },
): Promise<PayrollLoanRow[]> {
  const { data, error } = await client.rpc("list_payroll_loans", {
    p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: options?.employeeId ?? null, p_status: options?.status ?? null,
  });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollLoanRow);
}

export async function listPayrollRuns(
  client: PayrollQueryClient, tenantId: string, actorAuthUserId: string, options?: { periodId?: string | null; status?: string | null },
): Promise<PayrollRunRow[]> {
  const { data, error } = await client.rpc("list_payroll_runs", {
    p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_period_id: options?.periodId ?? null, p_status: options?.status ?? null,
  });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollRunRow);
}

export async function getPayrollRun(client: PayrollQueryClient, runId: string, actorAuthUserId: string): Promise<PayrollRunRow> {
  const { data, error } = await client.rpc("get_payroll_run", { p_run_id: runId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return parsePayrollRunRow(data as Record<string, unknown>);
}

export async function listPayrollRunEmployeeResults(client: PayrollQueryClient, runId: string, actorAuthUserId: string): Promise<PayrollRunEmployeeResultRow[]> {
  const { data, error } = await client.rpc("list_payroll_run_employee_results", { p_run_id: runId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollRunEmployeeResultRow);
}

export async function listPayrollCalculationLines(client: PayrollQueryClient, runId: string, employeeId: string, actorAuthUserId: string): Promise<PayrollCalculationLineRow[]> {
  const { data, error } = await client.rpc("list_payroll_calculation_lines", { p_run_id: runId, p_employee_id: employeeId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollCalculationLineRow);
}

export async function listPayrollExceptions(client: PayrollQueryClient, runId: string, actorAuthUserId: string, status?: string | null): Promise<PayrollExceptionRow[]> {
  const { data, error } = await client.rpc("list_payroll_exceptions", { p_run_id: runId, p_status: status ?? null, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollExceptionRow);
}

export async function listMyPayslips(client: PayrollQueryClient, tenantId: string, actorAuthUserId: string): Promise<PayslipRow[]> {
  const { data, error } = await client.rpc("list_my_payslips", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayslipRow);
}

export async function getPayslip(client: PayrollQueryClient, payslipId: string, actorAuthUserId: string): Promise<PayslipRow> {
  const { data, error } = await client.rpc("get_payslip", { p_payslip_id: payslipId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return parsePayslipRow(data as Record<string, unknown>);
}

export async function listPayslips(
  client: PayrollQueryClient, tenantId: string, actorAuthUserId: string, options?: { employeeId?: string | null; periodId?: string | null },
): Promise<PayslipRow[]> {
  const { data, error } = await client.rpc("list_payslips", {
    p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId, p_employee_id: options?.employeeId ?? null, p_period_id: options?.periodId ?? null,
  });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayslipRow);
}

export async function searchPayrollFinanceHandoffsPendingAcknowledgement(
  client: PayrollQueryClient, tenantId: string, actorAuthUserId: string,
): Promise<PayrollFinanceHandoffBatchRow[]> {
  const { data, error } = await client.rpc("search_payroll_finance_handoffs_pending_acknowledgement", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return rows(data).map(parsePayrollFinanceHandoffBatchRow);
}

export async function getPayrollFinanceHandoffBatch(client: PayrollQueryClient, batchId: string, actorAuthUserId: string): Promise<PayrollFinanceHandoffBatchRow> {
  const { data, error } = await client.rpc("get_payroll_finance_handoff_batch", { p_batch_id: batchId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  return parsePayrollFinanceHandoffBatchRow(data as Record<string, unknown>);
}

export async function getPayrollFinanceHandoffReconciliation(client: PayrollQueryClient, batchId: string, actorAuthUserId: string): Promise<PayrollFinanceHandoffReconciliation> {
  const { data, error } = await client.rpc("get_payroll_finance_handoff_reconciliation", { p_batch_id: batchId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new PayrollQueryError(error.message);
  const row = Array.isArray(data) ? (data[0] as Record<string, unknown>) : (data as Record<string, unknown>);
  return parsePayrollFinanceHandoffReconciliation(row);
}
