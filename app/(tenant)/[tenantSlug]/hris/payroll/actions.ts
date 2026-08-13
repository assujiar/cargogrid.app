"use server";

/**
 * HR/Payroll-approver Server Actions (HRT-282, CG-S12-HRT-010). Every write
 * here is permission-gated at the RPC layer (HRS:Edit/Approve/Override, or
 * FIN:Edit for the one Finance-side acknowledgement action) -- this file
 * never re-implements or weakens that gate, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createPayrollPeriod,
  freezePayrollPeriodInputs,
  reopenPayrollPeriodInputs,
  createPayrollComponent,
  createPayrollComponentVersion,
  approvePayrollComponentVersion,
  assignPayrollComponentToEmployee,
  decidePayrollReimbursementRequest,
  issuePayrollLoan,
  createPayrollRun,
  calculatePayrollRun,
  resolvePayrollException,
  waivePayrollException,
  submitPayrollRunForFinalization,
  finalizePayrollRun,
  cancelPayrollRun,
  prepareFinancePayrollDisbursementHandoffFromPayrollRun,
  acknowledgePayrollFinanceHandoffBatch,
  PayrollMutationError,
} from "../../../../../server/mutations/payroll.ts";

export interface PayrollAdminActionState {
  readonly error: string | null;
}

const OK: PayrollAdminActionState = { error: null };
const NO_ACCESS: PayrollAdminActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/payroll`;
}

export async function createPayrollPeriodAction(tenantSlug: string, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const periodType = String(formData.get("periodType") ?? "monthly");
  const periodStart = String(formData.get("periodStart") ?? "").trim();
  const periodEnd = String(formData.get("periodEnd") ?? "").trim();
  const payDate = String(formData.get("payDate") ?? "").trim();
  if (!code || !periodStart || !periodEnd || !payDate) return { error: "Code, period start/end, and pay date are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await createPayrollPeriod(supabase, { tenantId: access.tenant.id, orgUnitId: null, code, periodType, periodStart, periodEnd, payDate, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not create this payroll period: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function freezePayrollPeriodInputsAction(
  tenantSlug: string, periodId: string, expectedVersion: number, _prevState: PayrollAdminActionState, _formData: FormData,
): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await freezePayrollPeriodInputs(supabase, { periodId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not freeze this period's inputs: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

// HRT-282 Tier C batch review fix: this is, by the migration's own comment,
// the ONLY path back from input_frozen to open -- without a UI caller an HR
// admin who freezes a period and then finds a data error had no in-app way
// to correct it (spec-compliance lens Finding 1). Also now the correctly
// governed way to unwind a period after freeze's own Tier C-fixed
// advanced-run guard blocks a re-freeze.
export async function reopenPayrollPeriodInputsAction(
  tenantSlug: string, periodId: string, expectedVersion: number, _prevState: PayrollAdminActionState, formData: FormData,
): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to reopen a period's frozen inputs." };

  const supabase = await createSupabaseServerClient();
  try {
    await reopenPayrollPeriodInputs(supabase, { periodId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not reopen this period's inputs: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createPayrollComponentAction(tenantSlug: string, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const componentType = String(formData.get("componentType") ?? "");
  const glMappingCategory = String(formData.get("glMappingCategory") ?? "").trim();
  if (!code || !name || !componentType || !glMappingCategory) return { error: "Code, name, type, and GL mapping category are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    const component = await createPayrollComponent(supabase, { tenantId: access.tenant.id, code, name, componentType, glMappingCategory, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    const fixedAmountRaw = String(formData.get("fixedAmount") ?? "").trim();
    const calculationMethod = String(formData.get("calculationMethod") ?? "fixed_amount");
    if (fixedAmountRaw && (calculationMethod === "fixed_amount" || calculationMethod === "hourly_rate")) {
      const version = await createPayrollComponentVersion(supabase, {
        componentId: component.id, calculationMethod, fixedAmount: Number(fixedAmountRaw), percentageRate: null,
        percentageOfComponentId: null, currency: "IDR", effectiveFrom: new Date().toISOString().slice(0, 10),
        actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
      });
      await approvePayrollComponentVersion(supabase, { versionId: version.id, expectedVersion: version.recordVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    }
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not create this component: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function assignPayrollComponentAction(tenantSlug: string, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const componentId = String(formData.get("componentId") ?? "").trim();
  const effectiveFrom = String(formData.get("effectiveFrom") ?? "").trim();
  const manualAmountRaw = String(formData.get("manualAmount") ?? "").trim();
  if (!employeeId || !componentId || !effectiveFrom) return { error: "Employee, component, and effective date are all required." };

  const supabase = await createSupabaseServerClient();
  try {
    await assignPayrollComponentToEmployee(supabase, {
      tenantId: access.tenant.id, employeeId, componentId, overrideAmount: null, overridePercentage: null,
      manualAmount: manualAmountRaw ? Number(manualAmountRaw) : null, currency: "IDR", effectiveFrom, effectiveTo: null,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not assign this component: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function decidePayrollReimbursementAction(
  tenantSlug: string, requestId: string, expectedVersion: number, decision: "approve" | "reject", _prevState: PayrollAdminActionState, formData: FormData,
): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const decidedReason = String(formData.get("decidedReason") ?? "").trim();
  if (!decidedReason) return { error: "A reason is required to decide a reimbursement request." };

  const supabase = await createSupabaseServerClient();
  try {
    await decidePayrollReimbursementRequest(supabase, { requestId, expectedVersion, decision, decidedReason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not ${decision} this reimbursement request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function issuePayrollLoanAction(tenantSlug: string, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const employeeId = String(formData.get("employeeId") ?? "").trim();
  const principalAmount = Number(formData.get("principalAmount") ?? 0);
  const installmentAmount = Number(formData.get("installmentAmount") ?? 0);
  const termCount = Number(formData.get("termCount") ?? 0);
  if (!employeeId || principalAmount <= 0 || installmentAmount <= 0 || termCount <= 0) return { error: "Employee, principal, installment amount, and term count are all required and must be positive." };

  const supabase = await createSupabaseServerClient();
  try {
    await issuePayrollLoan(supabase, {
      tenantId: access.tenant.id, employeeId, principalAmount, currency: "IDR", installmentAmount, termCount,
      isOpeningBalance: false, openingRemainingInstallments: null, notes: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not issue this loan: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function createPayrollRunAction(tenantSlug: string, periodId: string, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const runType = String(formData.get("runType") ?? "regular");

  const supabase = await createSupabaseServerClient();
  try {
    await createPayrollRun(supabase, { tenantId: access.tenant.id, periodId, runType, adjustsRunId: null, currency: "IDR", idempotencyKey: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not create a run for this period: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function calculatePayrollRunAction(
  tenantSlug: string, runId: string, expectedVersion: number, _prevState: PayrollAdminActionState, _formData: FormData,
): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await calculatePayrollRun(supabase, { runId, expectedVersion, idempotencyKey: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not calculate this run: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function resolvePayrollExceptionAction(tenantSlug: string, exceptionId: string, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const resolutionNote = String(formData.get("resolutionNote") ?? "").trim();
  if (!resolutionNote) return { error: "A resolution note is required." };

  const supabase = await createSupabaseServerClient();
  try {
    await resolvePayrollException(supabase, { exceptionId, resolutionNote, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not resolve this exception: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function waivePayrollExceptionAction(tenantSlug: string, exceptionId: string, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const resolutionNote = String(formData.get("resolutionNote") ?? "").trim();
  if (!resolutionNote) return { error: "A resolution note is required to waive an exception." };

  const supabase = await createSupabaseServerClient();
  try {
    await waivePayrollException(supabase, { exceptionId, resolutionNote, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not waive this exception: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitPayrollRunForFinalizationAction(
  tenantSlug: string, runId: string, expectedVersion: number, _prevState: PayrollAdminActionState, _formData: FormData,
): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitPayrollRunForFinalization(supabase, { runId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not submit this run for finalization: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function finalizePayrollRunAction(
  tenantSlug: string, requestStepId: string, decision: "approved" | "rejected", _prevState: PayrollAdminActionState, formData: FormData,
): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to finalize or reject a payroll run." };

  const supabase = await createSupabaseServerClient();
  try {
    await finalizePayrollRun(supabase, { requestStepId, decision, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not ${decision === "approved" ? "finalize" : "reject"} this payroll run: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelPayrollRunAction(tenantSlug: string, runId: string, expectedVersion: number, _prevState: PayrollAdminActionState, formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel a payroll run." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelPayrollRun(supabase, { runId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not cancel this run: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function generateFinancePayrollHandoffAction(tenantSlug: string, runId: string, _prevState: PayrollAdminActionState, _formData: FormData): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await prepareFinancePayrollDisbursementHandoffFromPayrollRun(supabase, { tenantId: access.tenant.id, runId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not generate the Finance handoff for this run: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function acknowledgeFinancePayrollHandoffAction(
  tenantSlug: string, batchId: string, expectedVersion: number, _prevState: PayrollAdminActionState, _formData: FormData,
): Promise<PayrollAdminActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await acknowledgePayrollFinanceHandoffBatch(supabase, { batchId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not acknowledge this Finance handoff (requires FIN:Edit): ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
