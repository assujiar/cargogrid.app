/**
 * Overtime and Timesheet mutation primitives (HRT-281, CG-S12-HRT-009). Thin,
 * typed wrappers around every write RPC in
 * supabase/migrations/20260730980000_create_hris_overtime_timesheet.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateOvertimeRequestInputSchema,
  CreateOvertimeRequestForEmployeeInputSchema,
  SubmitOvertimeRequestInputSchema,
  ReconcileOvertimeRequestActualInputSchema,
  DecideOvertimeRequestInputSchema,
  CancelOvertimeRequestInputSchema,
  CreateTimesheetEntryInputSchema,
  CreateTimesheetEntryForEmployeeInputSchema,
  UpdateTimesheetEntryDraftInputSchema,
  SubmitTimesheetEntryInputSchema,
  DecideTimesheetEntryInputSchema,
  CancelTimesheetEntryInputSchema,
  CreateTimesheetPeriodInputSchema,
  SubmitTimesheetPeriodSummaryInputSchema,
  ApproveTimesheetPeriodSummaryInputSchema,
  RejectTimesheetPeriodSummaryInputSchema,
  LockTimesheetPeriodInputSchema,
  ReopenTimesheetPeriodInputSchema,
  ReopenTimesheetPeriodSummaryInputSchema,
  GeneratePayrollTimeInputInputSchema,
  GeneratePayrollTimeInputsForPeriodInputSchema,
  CreateOvertimePolicyInputSchema,
  CreateOvertimePolicyVersionInputSchema,
  PublishOvertimePolicyVersionInputSchema,
  type CreateOvertimeRequestInput,
  type CreateOvertimeRequestForEmployeeInput,
  type SubmitOvertimeRequestInput,
  type ReconcileOvertimeRequestActualInput,
  type DecideOvertimeRequestInput,
  type CancelOvertimeRequestInput,
  type CreateTimesheetEntryInput,
  type CreateTimesheetEntryForEmployeeInput,
  type UpdateTimesheetEntryDraftInput,
  type SubmitTimesheetEntryInput,
  type DecideTimesheetEntryInput,
  type CancelTimesheetEntryInput,
  type CreateTimesheetPeriodInput,
  type SubmitTimesheetPeriodSummaryInput,
  type ApproveTimesheetPeriodSummaryInput,
  type RejectTimesheetPeriodSummaryInput,
  type LockTimesheetPeriodInput,
  type ReopenTimesheetPeriodInput,
  type ReopenTimesheetPeriodSummaryInput,
  type GeneratePayrollTimeInputInput,
  type GeneratePayrollTimeInputsForPeriodInput,
  type CreateOvertimePolicyInput,
  type CreateOvertimePolicyVersionInput,
  type PublishOvertimePolicyVersionInput,
} from "../contracts/overtime-timesheet/overtime-timesheet.ts";

export type OvertimeTimesheetMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const OVERTIME_TIMESHEET_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "employee_not_found",
  "employee_not_active",
  "no_eligible_policy",
  "invalid_request_type",
  "invalid_time_range",
  "reason_required",
  "invalid_break_minutes",
  "idempotency_key_conflict",
  "overtime_request_conflict",
  "schedule_assignment_not_found",
  "job_order_not_found",
  "shipment_order_not_found",
  "leave_overlap_conflict",
  "overtime_request_not_found",
  "self_approval_not_permitted",
  "invalid_decision",
  "invalid_transition",
  "stale_version",
  "attendance_evidence_required",
  "invalid_approved_minutes",
  "timesheet_period_locked",
  "payroll_input_already_generated",
  "work_date_required",
  "invalid_entry_minutes",
  "invalid_source",
  "timesheet_entry_not_found",
  "invalid_code",
  "invalid_date_range",
  "org_unit_not_found",
  "timesheet_period_overlap",
  "timesheet_period_not_found",
  "timesheet_period_summary_not_found",
  "period_has_unapproved_summaries",
  "invalid_name",
  "policy_not_found",
  "policy_version_not_found",
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
] as const;

export type KnownOvertimeTimesheetMutationErrorCode = (typeof OVERTIME_TIMESHEET_KNOWN_MUTATION_ERROR_CODES)[number];
export type OvertimeTimesheetMutationErrorCode = KnownOvertimeTimesheetMutationErrorCode | "mutation_failed";

export class OvertimeTimesheetMutationError extends Error {
  readonly code: OvertimeTimesheetMutationErrorCode;

  constructor(code: OvertimeTimesheetMutationErrorCode, message: string) {
    super(message);
    this.name = "OvertimeTimesheetMutationError";
    this.code = code;
  }
}

function classifyError(message: string): OvertimeTimesheetMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (OVERTIME_TIMESHEET_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownOvertimeTimesheetMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export async function createOvertimeRequest(client: OvertimeTimesheetMutationRpcClient, input: CreateOvertimeRequestInput): Promise<Record<string, unknown>> {
  const parsed = CreateOvertimeRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("create_overtime_request", {
    p_tenant_id: parsed.tenantId,
    p_request_type: parsed.requestType,
    p_requested_start_at: parsed.requestedStartAt,
    p_requested_end_at: parsed.requestedEndAt,
    p_unpaid_break_minutes: parsed.unpaidBreakMinutes,
    p_reason: parsed.reason,
    p_schedule_assignment_id: parsed.scheduleAssignmentId,
    p_job_order_id: parsed.jobOrderId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "create_overtime_request returned no row");
  return row;
}

export async function createOvertimeRequestForEmployee(client: OvertimeTimesheetMutationRpcClient, input: CreateOvertimeRequestForEmployeeInput): Promise<Record<string, unknown>> {
  const parsed = CreateOvertimeRequestForEmployeeInputSchema.parse(input);
  const { data, error } = await client.rpc("create_overtime_request_for_employee", {
    p_tenant_id: parsed.tenantId,
    p_employee_id: parsed.employeeId,
    p_request_type: parsed.requestType,
    p_requested_start_at: parsed.requestedStartAt,
    p_requested_end_at: parsed.requestedEndAt,
    p_unpaid_break_minutes: parsed.unpaidBreakMinutes,
    p_reason: parsed.reason,
    p_schedule_assignment_id: parsed.scheduleAssignmentId,
    p_job_order_id: parsed.jobOrderId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "create_overtime_request_for_employee returned no row");
  return row;
}

export async function submitOvertimeRequest(client: OvertimeTimesheetMutationRpcClient, input: SubmitOvertimeRequestInput): Promise<Record<string, unknown>> {
  const parsed = SubmitOvertimeRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_overtime_request", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "submit_overtime_request returned no row");
  return row;
}

export async function reconcileOvertimeRequestActual(client: OvertimeTimesheetMutationRpcClient, input: ReconcileOvertimeRequestActualInput): Promise<Record<string, unknown>> {
  const parsed = ReconcileOvertimeRequestActualInputSchema.parse(input);
  const { data, error } = await client.rpc("reconcile_overtime_request_actual", {
    p_request_id: parsed.requestId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "reconcile_overtime_request_actual returned no row");
  return row;
}

export async function decideOvertimeRequest(client: OvertimeTimesheetMutationRpcClient, input: DecideOvertimeRequestInput): Promise<Record<string, unknown>> {
  const parsed = DecideOvertimeRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_overtime_request", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decided_reason: parsed.decidedReason,
    p_approved_minutes_override: parsed.approvedMinutesOverride,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "decide_overtime_request returned no row");
  return row;
}

export async function cancelOvertimeRequest(client: OvertimeTimesheetMutationRpcClient, input: CancelOvertimeRequestInput): Promise<Record<string, unknown>> {
  const parsed = CancelOvertimeRequestInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_overtime_request", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "cancel_overtime_request returned no row");
  return row;
}

export async function createTimesheetEntry(client: OvertimeTimesheetMutationRpcClient, input: CreateTimesheetEntryInput): Promise<Record<string, unknown>> {
  const parsed = CreateTimesheetEntryInputSchema.parse(input);
  const { data, error } = await client.rpc("create_timesheet_entry", {
    p_tenant_id: parsed.tenantId,
    p_work_date: parsed.workDate,
    p_entry_minutes: parsed.entryMinutes,
    p_unpaid_break_minutes: parsed.unpaidBreakMinutes,
    p_job_order_id: parsed.jobOrderId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_schedule_assignment_id: parsed.scheduleAssignmentId,
    p_notes: parsed.notes,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "create_timesheet_entry returned no row");
  return row;
}

export async function createTimesheetEntryForEmployee(client: OvertimeTimesheetMutationRpcClient, input: CreateTimesheetEntryForEmployeeInput): Promise<Record<string, unknown>> {
  const parsed = CreateTimesheetEntryForEmployeeInputSchema.parse(input);
  const { data, error } = await client.rpc("create_timesheet_entry_for_employee", {
    p_tenant_id: parsed.tenantId,
    p_employee_id: parsed.employeeId,
    p_work_date: parsed.workDate,
    p_entry_minutes: parsed.entryMinutes,
    p_unpaid_break_minutes: parsed.unpaidBreakMinutes,
    p_job_order_id: parsed.jobOrderId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_schedule_assignment_id: parsed.scheduleAssignmentId,
    p_notes: parsed.notes,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "create_timesheet_entry_for_employee returned no row");
  return row;
}

export async function updateTimesheetEntryDraft(client: OvertimeTimesheetMutationRpcClient, input: UpdateTimesheetEntryDraftInput): Promise<Record<string, unknown>> {
  const parsed = UpdateTimesheetEntryDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("update_timesheet_entry_draft", {
    p_entry_id: parsed.entryId,
    p_expected_version: parsed.expectedVersion,
    p_entry_minutes: parsed.entryMinutes,
    p_unpaid_break_minutes: parsed.unpaidBreakMinutes,
    p_job_order_id: parsed.jobOrderId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_notes: parsed.notes,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "update_timesheet_entry_draft returned no row");
  return row;
}

export async function submitTimesheetEntry(client: OvertimeTimesheetMutationRpcClient, input: SubmitTimesheetEntryInput): Promise<Record<string, unknown>> {
  const parsed = SubmitTimesheetEntryInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_timesheet_entry", {
    p_entry_id: parsed.entryId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "submit_timesheet_entry returned no row");
  return row;
}

export async function decideTimesheetEntry(client: OvertimeTimesheetMutationRpcClient, input: DecideTimesheetEntryInput): Promise<Record<string, unknown>> {
  const parsed = DecideTimesheetEntryInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_timesheet_entry", {
    p_entry_id: parsed.entryId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decided_reason: parsed.decidedReason,
    p_approved_minutes_override: parsed.approvedMinutesOverride,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "decide_timesheet_entry returned no row");
  return row;
}

export async function cancelTimesheetEntry(client: OvertimeTimesheetMutationRpcClient, input: CancelTimesheetEntryInput): Promise<Record<string, unknown>> {
  const parsed = CancelTimesheetEntryInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_timesheet_entry", {
    p_entry_id: parsed.entryId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "cancel_timesheet_entry returned no row");
  return row;
}

export async function createTimesheetPeriod(client: OvertimeTimesheetMutationRpcClient, input: CreateTimesheetPeriodInput): Promise<Record<string, unknown>> {
  const parsed = CreateTimesheetPeriodInputSchema.parse(input);
  const { data, error } = await client.rpc("create_timesheet_period", {
    p_tenant_id: parsed.tenantId,
    p_org_unit_id: parsed.orgUnitId,
    p_code: parsed.code,
    p_period_start: parsed.periodStart,
    p_period_end: parsed.periodEnd,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "create_timesheet_period returned no row");
  return row;
}

export async function submitTimesheetPeriodSummary(client: OvertimeTimesheetMutationRpcClient, input: SubmitTimesheetPeriodSummaryInput): Promise<Record<string, unknown>> {
  const parsed = SubmitTimesheetPeriodSummaryInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_timesheet_period_summary", {
    p_period_id: parsed.periodId,
    p_employee_id: parsed.employeeId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "submit_timesheet_period_summary returned no row");
  return row;
}

export async function approveTimesheetPeriodSummary(client: OvertimeTimesheetMutationRpcClient, input: ApproveTimesheetPeriodSummaryInput): Promise<Record<string, unknown>> {
  const parsed = ApproveTimesheetPeriodSummaryInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_timesheet_period_summary", {
    p_summary_id: parsed.summaryId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "approve_timesheet_period_summary returned no row");
  return row;
}

export async function rejectTimesheetPeriodSummary(client: OvertimeTimesheetMutationRpcClient, input: RejectTimesheetPeriodSummaryInput): Promise<Record<string, unknown>> {
  const parsed = RejectTimesheetPeriodSummaryInputSchema.parse(input);
  const { data, error } = await client.rpc("reject_timesheet_period_summary", {
    p_summary_id: parsed.summaryId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "reject_timesheet_period_summary returned no row");
  return row;
}

export async function lockTimesheetPeriod(client: OvertimeTimesheetMutationRpcClient, input: LockTimesheetPeriodInput): Promise<Record<string, unknown>> {
  const parsed = LockTimesheetPeriodInputSchema.parse(input);
  const { data, error } = await client.rpc("lock_timesheet_period", {
    p_period_id: parsed.periodId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "lock_timesheet_period returned no row");
  return row;
}

export async function reopenTimesheetPeriod(client: OvertimeTimesheetMutationRpcClient, input: ReopenTimesheetPeriodInput): Promise<Record<string, unknown>> {
  const parsed = ReopenTimesheetPeriodInputSchema.parse(input);
  const { data, error } = await client.rpc("reopen_timesheet_period", {
    p_period_id: parsed.periodId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "reopen_timesheet_period returned no row");
  return row;
}

export async function reopenTimesheetPeriodSummary(client: OvertimeTimesheetMutationRpcClient, input: ReopenTimesheetPeriodSummaryInput): Promise<Record<string, unknown>> {
  const parsed = ReopenTimesheetPeriodSummaryInputSchema.parse(input);
  const { data, error } = await client.rpc("reopen_timesheet_period_summary", {
    p_summary_id: parsed.summaryId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "reopen_timesheet_period_summary returned no row");
  return row;
}

export async function generatePayrollTimeInput(client: OvertimeTimesheetMutationRpcClient, input: GeneratePayrollTimeInputInput): Promise<Record<string, unknown>> {
  const parsed = GeneratePayrollTimeInputInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_payroll_time_input", {
    p_period_id: parsed.periodId,
    p_employee_id: parsed.employeeId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "generate_payroll_time_input returned no row");
  return row;
}

export async function generatePayrollTimeInputsForPeriod(client: OvertimeTimesheetMutationRpcClient, input: GeneratePayrollTimeInputsForPeriodInput): Promise<Record<string, unknown>[]> {
  const parsed = GeneratePayrollTimeInputsForPeriodInputSchema.parse(input);
  const { data, error } = await client.rpc("generate_payroll_time_inputs_for_period", {
    p_period_id: parsed.periodId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function createOvertimePolicy(client: OvertimeTimesheetMutationRpcClient, input: CreateOvertimePolicyInput): Promise<Record<string, unknown>> {
  const parsed = CreateOvertimePolicyInputSchema.parse(input);
  const { data, error } = await client.rpc("create_overtime_policy", {
    p_tenant_id: parsed.tenantId,
    p_org_unit_id: parsed.orgUnitId,
    p_name: parsed.name,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "create_overtime_policy returned no row");
  return row;
}

export async function createOvertimePolicyVersion(client: OvertimeTimesheetMutationRpcClient, input: CreateOvertimePolicyVersionInput): Promise<Record<string, unknown>> {
  const parsed = CreateOvertimePolicyVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_overtime_policy_version", {
    p_policy_id: parsed.policyId,
    p_rounding_increment_minutes: parsed.roundingIncrementMinutes,
    p_rounding_mode: parsed.roundingMode,
    p_min_overtime_minutes: parsed.minOvertimeMinutes,
    p_daily_overtime_cap_minutes: parsed.dailyOvertimeCapMinutes,
    p_weekly_overtime_cap_minutes: parsed.weeklyOvertimeCapMinutes,
    p_standard_workday_minutes: parsed.standardWorkdayMinutes,
    p_default_break_deduction_minutes: parsed.defaultBreakDeductionMinutes,
    p_requires_pre_approval: parsed.requiresPreApproval,
    p_effective_from: parsed.effectiveFrom,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "create_overtime_policy_version returned no row");
  return row;
}

export async function publishOvertimePolicyVersion(client: OvertimeTimesheetMutationRpcClient, input: PublishOvertimePolicyVersionInput): Promise<Record<string, unknown>> {
  const parsed = PublishOvertimePolicyVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_overtime_policy_version", {
    p_version_id: parsed.versionId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new OvertimeTimesheetMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new OvertimeTimesheetMutationError("mutation_failed", "publish_overtime_policy_version returned no row");
  return row;
}
