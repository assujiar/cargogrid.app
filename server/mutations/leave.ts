/**
 * Leave, Permit and Business Trip mutation primitives (HRT-280,
 * CG-S12-HRT-008). Thin, typed wrappers around every write RPC in
 * supabase/migrations/20260730930000_create_hris_leave_permit_business_trip.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateLeaveTypeInputSchema,
  PublishLeaveTypeInputSchema,
  CreateLeaveTypePolicyVersionInputSchema,
  PublishLeaveTypePolicyVersionInputSchema,
  CreateLeaveRequestInputSchema,
  CreateLeaveRequestForEmployeeInputSchema,
  UpdateLeaveRequestDraftInputSchema,
  SubmitLeaveRequestInputSchema,
  DecideLeaveRequestInputSchema,
  CancelLeaveRequestInputSchema,
  AdjustLeaveBalanceInputSchema,
  LoadOpeningLeaveBalanceInputSchema,
  RunLeaveAccrualBatchInputSchema,
  RunLeaveCarryForwardBatchInputSchema,
  CancelConflictingScheduleForLeaveInputSchema,
  SyncEmployeeLeaveLifecycleStatusInputSchema,
  ApproveLeaveForPayrollInputInputSchema,
  type CreateLeaveTypeInput,
  type PublishLeaveTypeInput,
  type CreateLeaveTypePolicyVersionInput,
  type PublishLeaveTypePolicyVersionInput,
  type CreateLeaveRequestInput,
  type CreateLeaveRequestForEmployeeInput,
  type UpdateLeaveRequestDraftInput,
  type SubmitLeaveRequestInput,
  type DecideLeaveRequestInput,
  type CancelLeaveRequestInput,
  type AdjustLeaveBalanceInput,
  type LoadOpeningLeaveBalanceInput,
  type RunLeaveAccrualBatchInput,
  type RunLeaveCarryForwardBatchInput,
  type CancelConflictingScheduleForLeaveInput,
  type SyncEmployeeLeaveLifecycleStatusInput,
  type ApproveLeaveForPayrollInputInput,
} from "../contracts/leave/leave.ts";
import { resolveRequestClientIp } from "../../lib/security/client-ip.ts";

export type LeaveMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const LEAVE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "employee_not_found",
  "employee_not_active",
  "leave_type_not_available",
  "leave_type_not_found",
  "no_eligible_policy",
  "duplicate_leave_type_code",
  "duplicate_policy_effective_date",
  "org_unit_not_found",
  "invalid_category",
  "invalid_date_range",
  "invalid_units",
  "invalid_period",
  "invalid_transition",
  "destination_not_applicable",
  "destination_required",
  "evidence_required",
  "evidence_file_not_found",
  "evidence_file_infected",
  "evidence_file_not_scanned",
  "idempotency_key_conflict",
  "idempotency_key_required",
  "max_consecutive_units_exceeded",
  "insufficient_balance",
  "min_notice_not_met",
  "eligibility_not_met",
  "leave_request_overlap",
  "leave_request_not_found",
  "leave_request_no_longer_applicable",
  "approval_definition_not_configured",
  "approval_step_not_found",
  "not_a_leave_request_approval",
  "coverage_below_minimum",
  "no_conflicting_schedule",
  "work_date_out_of_range",
  "stale_version",
  "reason_required",
  // HRT-294 (CG-S12-HRT-022, ISS-2026-114): raised by app.publish_leave_type_policy_version
  // since HRT-280's own creation migration, never added here (API-parity gap).
  "policy_version_not_found",
] as const;

export type KnownLeaveMutationErrorCode = (typeof LEAVE_KNOWN_MUTATION_ERROR_CODES)[number];
export type LeaveMutationErrorCode = KnownLeaveMutationErrorCode | "mutation_failed";

export class LeaveMutationError extends Error {
  readonly code: LeaveMutationErrorCode;

  constructor(code: LeaveMutationErrorCode, message: string) {
    super(message);
    this.name = "LeaveMutationError";
    this.code = code;
  }
}

function classifyError(message: string): LeaveMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  if (prefix && (LEAVE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix)) {
    return prefix as KnownLeaveMutationErrorCode;
  }
  return "mutation_failed";
}

async function callRpc<T>(client: LeaveMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<T> {
  const { data, error } = await client.rpc(fn, args);
  if (error) throw new LeaveMutationError(classifyError(error.message), error.message);
  return data as T;
}

export async function createLeaveType(client: LeaveMutationRpcClient, input: CreateLeaveTypeInput) {
  const v = CreateLeaveTypeInputSchema.parse(input);
  return callRpc(client, "create_leave_type", {
    p_tenant_id: v.tenantId,
    p_code: v.code,
    p_name: v.name,
    p_category: v.category,
    p_requires_balance: v.requiresBalance,
    p_requires_evidence: v.requiresEvidence,
    p_evidence_classification: v.evidenceClassification,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function publishLeaveType(client: LeaveMutationRpcClient, input: PublishLeaveTypeInput) {
  const v = PublishLeaveTypeInputSchema.parse(input);
  return callRpc(client, "publish_leave_type", {
    p_leave_type_id: v.leaveTypeId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

export async function createLeaveTypePolicyVersion(client: LeaveMutationRpcClient, input: CreateLeaveTypePolicyVersionInput) {
  const v = CreateLeaveTypePolicyVersionInputSchema.parse(input);
  return callRpc(client, "create_leave_type_policy_version", {
    p_leave_type_id: v.leaveTypeId,
    p_org_unit_id: v.orgUnitId,
    p_effective_from: v.effectiveFrom,
    p_accrual_frequency: v.accrualFrequency,
    p_accrual_amount_per_period: v.accrualAmountPerPeriod,
    p_accrual_max_balance: v.accrualMaxBalance,
    p_carry_forward_max_units: v.carryForwardMaxUnits,
    p_min_notice_days: v.minNoticeDays,
    p_max_consecutive_units: v.maxConsecutiveUnits,
    p_eligibility_min_tenure_days: v.eligibilityMinTenureDays,
    p_negative_balance_allowed: v.negativeBalanceAllowed,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function publishLeaveTypePolicyVersion(client: LeaveMutationRpcClient, input: PublishLeaveTypePolicyVersionInput) {
  const v = PublishLeaveTypePolicyVersionInputSchema.parse(input);
  return callRpc(client, "publish_leave_type_policy_version", {
    p_version_id: v.versionId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}

export async function createLeaveRequest(client: LeaveMutationRpcClient, input: CreateLeaveRequestInput) {
  const v = CreateLeaveRequestInputSchema.parse(input);
  return callRpc(client, "create_leave_request", {
    p_tenant_id: v.tenantId,
    p_leave_type_id: v.leaveTypeId,
    p_date_from: v.dateFrom,
    p_date_to: v.dateTo,
    p_day_portion: v.dayPortion,
    p_reason: v.reason,
    p_destination: v.destination,
    p_evidence_file_id: v.evidenceFileId,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function createLeaveRequestForEmployee(client: LeaveMutationRpcClient, input: CreateLeaveRequestForEmployeeInput) {
  const v = CreateLeaveRequestForEmployeeInputSchema.parse(input);
  return callRpc(client, "create_leave_request_for_employee", {
    p_tenant_id: v.tenantId,
    p_employee_id: v.employeeId,
    p_leave_type_id: v.leaveTypeId,
    p_date_from: v.dateFrom,
    p_date_to: v.dateTo,
    p_day_portion: v.dayPortion,
    p_reason: v.reason,
    p_destination: v.destination,
    p_evidence_file_id: v.evidenceFileId,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function updateLeaveRequestDraft(client: LeaveMutationRpcClient, input: UpdateLeaveRequestDraftInput) {
  const v = UpdateLeaveRequestDraftInputSchema.parse(input);
  return callRpc(client, "update_leave_request_draft", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_date_from: v.dateFrom,
    p_date_to: v.dateTo,
    p_day_portion: v.dayPortion,
    p_reason: v.reason,
    p_destination: v.destination,
    p_evidence_file_id: v.evidenceFileId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function submitLeaveRequest(client: LeaveMutationRpcClient, input: SubmitLeaveRequestInput) {
  const v = SubmitLeaveRequestInputSchema.parse(input);
  return callRpc(client, "submit_leave_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function decideLeaveRequest(client: LeaveMutationRpcClient, input: DecideLeaveRequestInput) {
  const v = DecideLeaveRequestInputSchema.parse(input);
  return callRpc(client, "decide_leave_request", {
    p_request_step_id: v.requestStepId,
    p_decision: v.decision,
    p_reason: v.reason,
    p_override_coverage: v.overrideCoverage,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function cancelLeaveRequest(client: LeaveMutationRpcClient, input: CancelLeaveRequestInput) {
  const v = CancelLeaveRequestInputSchema.parse(input);
  return callRpc(client, "cancel_leave_request", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function adjustLeaveBalance(client: LeaveMutationRpcClient, input: AdjustLeaveBalanceInput) {
  const v = AdjustLeaveBalanceInputSchema.parse(input);
  return callRpc(client, "adjust_leave_balance", {
    p_tenant_id: v.tenantId,
    p_employee_id: v.employeeId,
    p_leave_type_id: v.leaveTypeId,
    p_units: v.units,
    p_effective_date: v.effectiveDate,
    p_reason: v.reason,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function loadOpeningLeaveBalance(client: LeaveMutationRpcClient, input: LoadOpeningLeaveBalanceInput) {
  const v = LoadOpeningLeaveBalanceInputSchema.parse(input);
  return callRpc(client, "load_opening_leave_balance", {
    p_tenant_id: v.tenantId,
    p_employee_id: v.employeeId,
    p_leave_type_id: v.leaveTypeId,
    p_units: v.units,
    p_as_of_date: v.asOfDate,
    p_source_reference: v.sourceReference,
    p_idempotency_key: v.idempotencyKey,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function runLeaveAccrualBatch(client: LeaveMutationRpcClient, input: RunLeaveAccrualBatchInput) {
  const v = RunLeaveAccrualBatchInputSchema.parse(input);
  return callRpc(client, "run_leave_accrual_batch", {
    p_tenant_id: v.tenantId,
    p_leave_type_id: v.leaveTypeId,
    p_as_of_date: v.asOfDate,
    p_period_label: v.periodLabel,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function runLeaveCarryForwardBatch(client: LeaveMutationRpcClient, input: RunLeaveCarryForwardBatchInput) {
  const v = RunLeaveCarryForwardBatchInputSchema.parse(input);
  return callRpc(client, "run_leave_carry_forward_batch", {
    p_tenant_id: v.tenantId,
    p_leave_type_id: v.leaveTypeId,
    p_effective_date: v.effectiveDate,
    p_period_label: v.periodLabel,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function cancelConflictingScheduleForLeave(client: LeaveMutationRpcClient, input: CancelConflictingScheduleForLeaveInput) {
  const v = CancelConflictingScheduleForLeaveInputSchema.parse(input);
  return callRpc(client, "cancel_conflicting_schedule_assignment_for_leave", {
    p_leave_request_id: v.leaveRequestId,
    p_work_date: v.workDate,
    p_expected_version: v.expectedVersion,
    p_reason: v.reason,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function syncEmployeeLeaveLifecycleStatus(client: LeaveMutationRpcClient, input: SyncEmployeeLeaveLifecycleStatusInput) {
  const v = SyncEmployeeLeaveLifecycleStatusInputSchema.parse(input);
  return callRpc(client, "sync_employee_leave_lifecycle_status", {
    p_tenant_id: v.tenantId,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
  });
}

export async function approveLeaveForPayrollInput(client: LeaveMutationRpcClient, input: ApproveLeaveForPayrollInputInput) {
  const v = ApproveLeaveForPayrollInputInputSchema.parse(input);
  return callRpc(client, "approve_leave_for_payroll_input", {
    p_request_id: v.requestId,
    p_expected_version: v.expectedVersion,
    p_actor_auth_user_id: v.actorAuthUserId,
    p_actor_label: v.actorLabel,
    // ISS-2026-302: read here rather than threaded through every caller -- a security
    // control a call site can forget to pass is not a control. Null outside a request.
    p_client_ip: await resolveRequestClientIp(),
  });
}
