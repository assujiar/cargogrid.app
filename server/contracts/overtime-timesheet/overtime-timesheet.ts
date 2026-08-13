/**
 * Overtime and Timesheet contract (HRT-281, CG-S12-HRT-009). Mirrors
 * supabase/migrations/20260730980000_create_hris_overtime_timesheet.sql's
 * policy/overtime-request/timesheet-entry/period/summary/payroll-input
 * shapes and their RPCs. Follows the exact directory convention HRT-278/
 * 279/280 established: Zod schemas here, list/read projections in
 * server/queries/overtime-timesheet.ts, RPC-calling mutation wrappers with
 * an enumerated error-code type in server/mutations/overtime-timesheet.ts.
 *
 * Decision (see the migration's own header): self-service create RPCs carry
 * no employee-id-shaped input field at all -- there is nothing here to
 * validate against spoofing because there is no such field to spoof.
 */

import { z } from "zod";

export const REQUEST_TYPES = ["planned", "emergency_after_the_fact"] as const;
export const RequestTypeSchema = z.enum(REQUEST_TYPES);
export type RequestType = z.infer<typeof RequestTypeSchema>;

export const OVERTIME_REQUEST_STATUSES = ["draft", "pending_approval", "approved", "rejected", "cancelled"] as const;
export const OvertimeRequestStatusSchema = z.enum(OVERTIME_REQUEST_STATUSES);
export type OvertimeRequestStatus = z.infer<typeof OvertimeRequestStatusSchema>;

export const TIMESHEET_ENTRY_STATUSES = ["draft", "pending_approval", "approved", "rejected", "cancelled"] as const;
export const TimesheetEntryStatusSchema = z.enum(TIMESHEET_ENTRY_STATUSES);
export type TimesheetEntryStatus = z.infer<typeof TimesheetEntryStatusSchema>;

export const TIMESHEET_ENTRY_SOURCES = ["manual", "import", "attendance_derived"] as const;
export const TimesheetEntrySourceSchema = z.enum(TIMESHEET_ENTRY_SOURCES);
export type TimesheetEntrySource = z.infer<typeof TimesheetEntrySourceSchema>;

export const RECONCILIATION_STATUSES = ["not_reconciled", "matched", "mismatch", "no_attendance"] as const;
export const ReconciliationStatusSchema = z.enum(RECONCILIATION_STATUSES);
export type ReconciliationStatus = z.infer<typeof ReconciliationStatusSchema>;

export const ELIGIBLE_CLASSIFICATIONS = ["weekday", "weekend", "holiday"] as const;
export const EligibleClassificationSchema = z.enum(ELIGIBLE_CLASSIFICATIONS);
export type EligibleClassification = z.infer<typeof EligibleClassificationSchema>;

export const PAYROLL_INPUT_STATUSES = ["pending", "approved"] as const;
export const PayrollInputStatusSchema = z.enum(PAYROLL_INPUT_STATUSES);
export type PayrollInputStatus = z.infer<typeof PayrollInputStatusSchema>;

export const DECISIONS = ["approve", "reject"] as const;
export const DecisionSchema = z.enum(DECISIONS);
export type Decision = z.infer<typeof DecisionSchema>;

export const POLICY_STATUSES = ["draft", "published", "archived"] as const;
export const PolicyStatusSchema = z.enum(POLICY_STATUSES);
export type PolicyStatus = z.infer<typeof PolicyStatusSchema>;

export const POLICY_VERSION_STATUSES = ["draft", "published", "superseded"] as const;
export const PolicyVersionStatusSchema = z.enum(POLICY_VERSION_STATUSES);
export type PolicyVersionStatus = z.infer<typeof PolicyVersionStatusSchema>;

export const ROUNDING_MODES = ["nearest", "up", "down"] as const;
export const RoundingModeSchema = z.enum(ROUNDING_MODES);
export type RoundingMode = z.infer<typeof RoundingModeSchema>;

export const TIMESHEET_PERIOD_STATUSES = ["open", "locked"] as const;
export const TimesheetPeriodStatusSchema = z.enum(TIMESHEET_PERIOD_STATUSES);
export type TimesheetPeriodStatus = z.infer<typeof TimesheetPeriodStatusSchema>;

export const TIMESHEET_PERIOD_SUMMARY_STATUSES = ["pending", "submitted", "approved", "rejected"] as const;
export const TimesheetPeriodSummaryStatusSchema = z.enum(TIMESHEET_PERIOD_SUMMARY_STATUSES);
export type TimesheetPeriodSummaryStatus = z.infer<typeof TimesheetPeriodSummaryStatusSchema>;

export const PAYROLL_TIME_INPUT_STATUSES = ["active", "superseded"] as const;
export const PayrollTimeInputStatusSchema = z.enum(PAYROLL_TIME_INPUT_STATUSES);
export type PayrollTimeInputStatus = z.infer<typeof PayrollTimeInputStatusSchema>;

// --- Core rows ---

export const OvertimeRequestRowSchema = z.object({
  id: z.string().uuid(),
  workDate: z.string(),
  requestType: RequestTypeSchema,
  requestedStartAt: z.string(),
  requestedEndAt: z.string(),
  requestedMinutes: z.number().int().nonnegative(),
  unpaidBreakMinutes: z.number().int().nonnegative(),
  status: OvertimeRequestStatusSchema,
  reconciliationStatus: ReconciliationStatusSchema,
  eligibleMinutes: z.number().int().nonnegative().nullable(),
  eligibleClassification: EligibleClassificationSchema.nullable(),
  approvedMinutes: z.number().int().nonnegative().nullable(),
  payrollInputStatus: PayrollInputStatusSchema,
  reason: z.string().nullable().optional(),
  recordVersion: z.number().int().positive(),
});
export type OvertimeRequestRow = z.infer<typeof OvertimeRequestRowSchema>;

export function parseOvertimeRequestRow(row: Record<string, unknown>): OvertimeRequestRow {
  return OvertimeRequestRowSchema.parse({
    id: row.id,
    workDate: row.work_date,
    requestType: row.request_type,
    requestedStartAt: row.requested_start_at,
    requestedEndAt: row.requested_end_at,
    requestedMinutes: row.requested_minutes,
    unpaidBreakMinutes: row.unpaid_break_minutes,
    status: row.status,
    reconciliationStatus: row.reconciliation_status,
    eligibleMinutes: row.eligible_minutes ?? null,
    eligibleClassification: row.eligible_classification ?? null,
    approvedMinutes: row.approved_minutes ?? null,
    payrollInputStatus: row.payroll_input_status,
    reason: (row.reason as string | null | undefined) ?? undefined,
    recordVersion: row.record_version,
  });
}

export const OvertimeRequestAdminRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: z.string(),
  requestType: RequestTypeSchema,
  status: OvertimeRequestStatusSchema,
  requestedMinutes: z.number().int().nonnegative(),
  reconciliationStatus: ReconciliationStatusSchema,
  eligibleMinutes: z.number().int().nonnegative().nullable(),
  eligibleClassification: EligibleClassificationSchema.nullable(),
  approvedMinutes: z.number().int().nonnegative().nullable(),
  payrollInputStatus: PayrollInputStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type OvertimeRequestAdminRow = z.infer<typeof OvertimeRequestAdminRowSchema>;

export function parseOvertimeRequestAdminRow(row: Record<string, unknown>): OvertimeRequestAdminRow {
  return OvertimeRequestAdminRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    requestType: row.request_type,
    status: row.status,
    requestedMinutes: row.requested_minutes,
    reconciliationStatus: row.reconciliation_status,
    eligibleMinutes: row.eligible_minutes ?? null,
    eligibleClassification: row.eligible_classification ?? null,
    approvedMinutes: row.approved_minutes ?? null,
    payrollInputStatus: row.payroll_input_status,
    recordVersion: row.record_version,
  });
}

export const OvertimeRequestDetailSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: z.string(),
  requestType: RequestTypeSchema,
  requestedStartAt: z.string(),
  requestedEndAt: z.string(),
  requestedMinutes: z.number().int().nonnegative(),
  unpaidBreakMinutes: z.number().int().nonnegative(),
  reason: z.string().nullable(),
  scheduleAssignmentId: z.string().uuid().nullable(),
  jobOrderId: z.string().uuid().nullable(),
  jobNumber: z.string().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  shipmentNumber: z.string().nullable(),
  status: OvertimeRequestStatusSchema,
  reconciliationStatus: ReconciliationStatusSchema,
  reconciledActualMinutes: z.number().int().nullable(),
  eligibleMinutes: z.number().int().nonnegative().nullable(),
  eligibleClassification: EligibleClassificationSchema.nullable(),
  approvedMinutes: z.number().int().nonnegative().nullable(),
  decidedReason: z.string().nullable(),
  cancelReason: z.string().nullable(),
  payrollInputStatus: PayrollInputStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type OvertimeRequestDetail = z.infer<typeof OvertimeRequestDetailSchema>;

export function parseOvertimeRequestDetail(row: Record<string, unknown>): OvertimeRequestDetail {
  return OvertimeRequestDetailSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    requestType: row.request_type,
    requestedStartAt: row.requested_start_at,
    requestedEndAt: row.requested_end_at,
    requestedMinutes: row.requested_minutes,
    unpaidBreakMinutes: row.unpaid_break_minutes,
    reason: row.reason ?? null,
    scheduleAssignmentId: row.schedule_assignment_id ?? null,
    jobOrderId: row.job_order_id ?? null,
    jobNumber: row.job_number ?? null,
    shipmentOrderId: row.shipment_order_id ?? null,
    shipmentNumber: row.shipment_number ?? null,
    status: row.status,
    reconciliationStatus: row.reconciliation_status,
    reconciledActualMinutes: row.reconciled_actual_minutes ?? null,
    eligibleMinutes: row.eligible_minutes ?? null,
    eligibleClassification: row.eligible_classification ?? null,
    approvedMinutes: row.approved_minutes ?? null,
    decidedReason: row.decided_reason ?? null,
    cancelReason: row.cancel_reason ?? null,
    payrollInputStatus: row.payroll_input_status,
    recordVersion: row.record_version,
  });
}

export const TimesheetEntryRowSchema = z.object({
  id: z.string().uuid(),
  workDate: z.string(),
  entryMinutes: z.number().int().positive(),
  unpaidBreakMinutes: z.number().int().nonnegative(),
  jobOrderId: z.string().uuid().nullable(),
  jobNumber: z.string().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  shipmentNumber: z.string().nullable(),
  status: TimesheetEntryStatusSchema,
  reconciliationStatus: ReconciliationStatusSchema,
  eligibleMinutes: z.number().int().nonnegative().nullable(),
  approvedMinutes: z.number().int().nonnegative().nullable(),
  payrollInputStatus: PayrollInputStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type TimesheetEntryRow = z.infer<typeof TimesheetEntryRowSchema>;

export function parseTimesheetEntryRow(row: Record<string, unknown>): TimesheetEntryRow {
  return TimesheetEntryRowSchema.parse({
    id: row.id,
    workDate: row.work_date,
    entryMinutes: row.entry_minutes,
    unpaidBreakMinutes: row.unpaid_break_minutes,
    jobOrderId: row.job_order_id ?? null,
    jobNumber: row.job_number ?? null,
    shipmentOrderId: row.shipment_order_id ?? null,
    shipmentNumber: row.shipment_number ?? null,
    status: row.status,
    reconciliationStatus: row.reconciliation_status,
    eligibleMinutes: row.eligible_minutes ?? null,
    approvedMinutes: row.approved_minutes ?? null,
    payrollInputStatus: row.payroll_input_status,
    recordVersion: row.record_version,
  });
}

export const TimesheetEntryAdminRowSchema = TimesheetEntryRowSchema.extend({
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  employeeFullName: z.string(),
});
export type TimesheetEntryAdminRow = z.infer<typeof TimesheetEntryAdminRowSchema>;

export function parseTimesheetEntryAdminRow(row: Record<string, unknown>): TimesheetEntryAdminRow {
  return TimesheetEntryAdminRowSchema.parse({
    ...parseTimesheetEntryRow(row),
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
  });
}

export const TimesheetEntryDetailSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: z.string(),
  entryMinutes: z.number().int().positive(),
  unpaidBreakMinutes: z.number().int().nonnegative(),
  jobOrderId: z.string().uuid().nullable(),
  jobNumber: z.string().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  shipmentNumber: z.string().nullable(),
  notes: z.string().nullable(),
  status: TimesheetEntryStatusSchema,
  source: TimesheetEntrySourceSchema,
  reconciliationStatus: ReconciliationStatusSchema,
  reconciledDayActualMinutes: z.number().int().nullable(),
  eligibleMinutes: z.number().int().nonnegative().nullable(),
  approvedMinutes: z.number().int().nonnegative().nullable(),
  decidedReason: z.string().nullable(),
  cancelReason: z.string().nullable(),
  payrollInputStatus: PayrollInputStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type TimesheetEntryDetail = z.infer<typeof TimesheetEntryDetailSchema>;

export function parseTimesheetEntryDetail(row: Record<string, unknown>): TimesheetEntryDetail {
  return TimesheetEntryDetailSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    entryMinutes: row.entry_minutes,
    unpaidBreakMinutes: row.unpaid_break_minutes,
    jobOrderId: row.job_order_id ?? null,
    jobNumber: row.job_number ?? null,
    shipmentOrderId: row.shipment_order_id ?? null,
    shipmentNumber: row.shipment_number ?? null,
    notes: row.notes ?? null,
    status: row.status,
    source: row.source,
    reconciliationStatus: row.reconciliation_status,
    reconciledDayActualMinutes: row.reconciled_day_actual_minutes ?? null,
    eligibleMinutes: row.eligible_minutes ?? null,
    approvedMinutes: row.approved_minutes ?? null,
    decidedReason: row.decided_reason ?? null,
    cancelReason: row.cancel_reason ?? null,
    payrollInputStatus: row.payroll_input_status,
    recordVersion: row.record_version,
  });
}

export const TimesheetPeriodRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  code: z.string(),
  periodStart: z.string(),
  periodEnd: z.string(),
  status: TimesheetPeriodStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type TimesheetPeriodRow = z.infer<typeof TimesheetPeriodRowSchema>;

export function parseTimesheetPeriodRow(row: Record<string, unknown>): TimesheetPeriodRow {
  return TimesheetPeriodRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id ?? null,
    code: row.code,
    periodStart: row.period_start,
    periodEnd: row.period_end,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const TimesheetPeriodSummaryRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  timesheetPeriodId: z.string().uuid(),
  status: TimesheetPeriodSummaryStatusSchema,
  totalRegularMinutes: z.number().int().nonnegative(),
  totalOvertimeWeekdayMinutes: z.number().int().nonnegative(),
  totalOvertimeWeekendMinutes: z.number().int().nonnegative(),
  totalOvertimeHolidayMinutes: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
});
export type TimesheetPeriodSummaryRow = z.infer<typeof TimesheetPeriodSummaryRowSchema>;

export function parseTimesheetPeriodSummaryRow(row: Record<string, unknown>): TimesheetPeriodSummaryRow {
  return TimesheetPeriodSummaryRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    timesheetPeriodId: row.timesheet_period_id,
    status: row.status,
    totalRegularMinutes: row.total_regular_minutes,
    totalOvertimeWeekdayMinutes: row.total_overtime_weekday_minutes,
    totalOvertimeWeekendMinutes: row.total_overtime_weekend_minutes,
    totalOvertimeHolidayMinutes: row.total_overtime_holiday_minutes,
    recordVersion: row.record_version,
  });
}

export const TimesheetPeriodSummaryDetailSchema = TimesheetPeriodSummaryRowSchema.extend({
  entryCount: z.number().int().nonnegative(),
  overtimeRequestCount: z.number().int().nonnegative(),
  computedAt: z.string().nullable(),
  decidedReason: z.string().nullable(),
  reopenCount: z.number().int().nonnegative(),
  lastReopenReason: z.string().nullable(),
});
export type TimesheetPeriodSummaryDetail = z.infer<typeof TimesheetPeriodSummaryDetailSchema>;

export function parseTimesheetPeriodSummaryDetail(row: Record<string, unknown>): TimesheetPeriodSummaryDetail {
  return TimesheetPeriodSummaryDetailSchema.parse({
    ...parseTimesheetPeriodSummaryRow(row),
    entryCount: row.entry_count,
    overtimeRequestCount: row.overtime_request_count,
    computedAt: row.computed_at ?? null,
    decidedReason: row.decided_reason ?? null,
    reopenCount: row.reopen_count,
    lastReopenReason: row.last_reopen_reason ?? null,
  });
}

export const OvertimePolicyRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string(),
  status: PolicyStatusSchema,
  publishedVersionId: z.string().uuid().nullable(),
  publishedVersionNumber: z.number().int().nullable(),
  recordVersion: z.number().int().positive(),
});
export type OvertimePolicyRow = z.infer<typeof OvertimePolicyRowSchema>;

export function parseOvertimePolicyRow(row: Record<string, unknown>): OvertimePolicyRow {
  return OvertimePolicyRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id ?? null,
    name: row.name,
    status: row.status,
    publishedVersionId: row.published_version_id ?? null,
    publishedVersionNumber: row.published_version_number ?? null,
    recordVersion: row.record_version,
  });
}

export const OvertimePolicyVersionSchema = z.object({
  id: z.string().uuid(),
  policyId: z.string().uuid(),
  tenantId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: PolicyVersionStatusSchema,
  effectiveFrom: z.string(),
  roundingIncrementMinutes: z.number().int().positive(),
  roundingMode: RoundingModeSchema,
  minOvertimeMinutes: z.number().int().nonnegative(),
  dailyOvertimeCapMinutes: z.number().int().positive().nullable(),
  weeklyOvertimeCapMinutes: z.number().int().positive().nullable(),
  standardWorkdayMinutes: z.number().int().positive(),
  defaultBreakDeductionMinutes: z.number().int().nonnegative(),
  requiresPreApproval: z.boolean(),
  recordVersion: z.number().int().positive(),
});
export type OvertimePolicyVersion = z.infer<typeof OvertimePolicyVersionSchema>;

export function parseOvertimePolicyVersion(row: Record<string, unknown>): OvertimePolicyVersion {
  return OvertimePolicyVersionSchema.parse({
    id: row.id,
    policyId: row.policy_id,
    tenantId: row.tenant_id,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: row.effective_from,
    roundingIncrementMinutes: row.rounding_increment_minutes,
    roundingMode: row.rounding_mode,
    minOvertimeMinutes: row.min_overtime_minutes,
    dailyOvertimeCapMinutes: row.daily_overtime_cap_minutes ?? null,
    weeklyOvertimeCapMinutes: row.weekly_overtime_cap_minutes ?? null,
    standardWorkdayMinutes: row.standard_workday_minutes,
    defaultBreakDeductionMinutes: row.default_break_deduction_minutes,
    requiresPreApproval: row.requires_pre_approval,
    recordVersion: row.record_version,
  });
}

export const PayrollTimeInputRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  timesheetPeriodId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: PayrollTimeInputStatusSchema,
  regularMinutes: z.number().int().nonnegative(),
  overtimeWeekdayMinutes: z.number().int().nonnegative(),
  overtimeWeekendMinutes: z.number().int().nonnegative(),
  overtimeHolidayMinutes: z.number().int().nonnegative(),
  createdAt: z.string(),
});
export type PayrollTimeInputRow = z.infer<typeof PayrollTimeInputRowSchema>;

export function parsePayrollTimeInputRow(row: Record<string, unknown>): PayrollTimeInputRow {
  return PayrollTimeInputRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    timesheetPeriodId: row.timesheet_period_id,
    versionNumber: row.version_number,
    status: row.status,
    regularMinutes: row.regular_minutes,
    overtimeWeekdayMinutes: row.overtime_weekday_minutes,
    overtimeWeekendMinutes: row.overtime_weekend_minutes,
    overtimeHolidayMinutes: row.overtime_holiday_minutes,
    createdAt: row.created_at,
  });
}

export const PayrollTimeInputDetailSchema = PayrollTimeInputRowSchema.extend({
  sourceEntryIds: z.array(z.string().uuid()),
  sourceOvertimeRequestIds: z.array(z.string().uuid()),
});
export type PayrollTimeInputDetail = z.infer<typeof PayrollTimeInputDetailSchema>;

export function parsePayrollTimeInputDetail(row: Record<string, unknown>): PayrollTimeInputDetail {
  return PayrollTimeInputDetailSchema.parse({
    ...parsePayrollTimeInputRow(row),
    sourceEntryIds: row.source_entry_ids ?? [],
    sourceOvertimeRequestIds: row.source_overtime_request_ids ?? [],
  });
}

// --- Mutation inputs ---

export const CreateOvertimeRequestInputSchema = z.object({
  tenantId: z.string().uuid(),
  requestType: RequestTypeSchema,
  requestedStartAt: z.string().min(1),
  requestedEndAt: z.string().min(1),
  unpaidBreakMinutes: z.number().int().min(0),
  reason: z.string().min(1),
  scheduleAssignmentId: z.string().uuid().nullable(),
  jobOrderId: z.string().uuid().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateOvertimeRequestInput = z.infer<typeof CreateOvertimeRequestInputSchema>;

export const CreateOvertimeRequestForEmployeeInputSchema = CreateOvertimeRequestInputSchema.extend({
  employeeId: z.string().uuid(),
});
export type CreateOvertimeRequestForEmployeeInput = z.infer<typeof CreateOvertimeRequestForEmployeeInputSchema>;

export const SubmitOvertimeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SubmitOvertimeRequestInput = z.infer<typeof SubmitOvertimeRequestInputSchema>;

export const ReconcileOvertimeRequestActualInputSchema = z.object({
  requestId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReconcileOvertimeRequestActualInput = z.infer<typeof ReconcileOvertimeRequestActualInputSchema>;

export const DecideOvertimeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: DecisionSchema,
  decidedReason: z.string().min(1),
  approvedMinutesOverride: z.number().int().nonnegative().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideOvertimeRequestInput = z.infer<typeof DecideOvertimeRequestInputSchema>;

export const CancelOvertimeRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelOvertimeRequestInput = z.infer<typeof CancelOvertimeRequestInputSchema>;

export const CreateTimesheetEntryInputSchema = z.object({
  tenantId: z.string().uuid(),
  workDate: z.string().min(1),
  entryMinutes: z.number().int().positive(),
  unpaidBreakMinutes: z.number().int().min(0),
  jobOrderId: z.string().uuid().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  scheduleAssignmentId: z.string().uuid().nullable(),
  notes: z.string().nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTimesheetEntryInput = z.infer<typeof CreateTimesheetEntryInputSchema>;

export const CreateTimesheetEntryForEmployeeInputSchema = CreateTimesheetEntryInputSchema.extend({
  employeeId: z.string().uuid(),
});
export type CreateTimesheetEntryForEmployeeInput = z.infer<typeof CreateTimesheetEntryForEmployeeInputSchema>;

export const UpdateTimesheetEntryDraftInputSchema = z.object({
  entryId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  entryMinutes: z.number().int().positive(),
  unpaidBreakMinutes: z.number().int().min(0),
  jobOrderId: z.string().uuid().nullable(),
  shipmentOrderId: z.string().uuid().nullable(),
  notes: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateTimesheetEntryDraftInput = z.infer<typeof UpdateTimesheetEntryDraftInputSchema>;

export const SubmitTimesheetEntryInputSchema = z.object({
  entryId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SubmitTimesheetEntryInput = z.infer<typeof SubmitTimesheetEntryInputSchema>;

export const DecideTimesheetEntryInputSchema = z.object({
  entryId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: DecisionSchema,
  decidedReason: z.string().min(1),
  approvedMinutesOverride: z.number().int().nonnegative().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideTimesheetEntryInput = z.infer<typeof DecideTimesheetEntryInputSchema>;

export const CancelTimesheetEntryInputSchema = z.object({
  entryId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelTimesheetEntryInput = z.infer<typeof CancelTimesheetEntryInputSchema>;

export const CreateTimesheetPeriodInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  code: z.string().min(1),
  periodStart: z.string().min(1),
  periodEnd: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateTimesheetPeriodInput = z.infer<typeof CreateTimesheetPeriodInputSchema>;

export const SubmitTimesheetPeriodSummaryInputSchema = z.object({
  periodId: z.string().uuid(),
  employeeId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SubmitTimesheetPeriodSummaryInput = z.infer<typeof SubmitTimesheetPeriodSummaryInputSchema>;

export const ApproveTimesheetPeriodSummaryInputSchema = z.object({
  summaryId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApproveTimesheetPeriodSummaryInput = z.infer<typeof ApproveTimesheetPeriodSummaryInputSchema>;

export const RejectTimesheetPeriodSummaryInputSchema = ApproveTimesheetPeriodSummaryInputSchema;
export type RejectTimesheetPeriodSummaryInput = z.infer<typeof RejectTimesheetPeriodSummaryInputSchema>;

export const LockTimesheetPeriodInputSchema = z.object({
  periodId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LockTimesheetPeriodInput = z.infer<typeof LockTimesheetPeriodInputSchema>;

export const ReopenTimesheetPeriodInputSchema = z.object({
  periodId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReopenTimesheetPeriodInput = z.infer<typeof ReopenTimesheetPeriodInputSchema>;

export const ReopenTimesheetPeriodSummaryInputSchema = z.object({
  summaryId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ReopenTimesheetPeriodSummaryInput = z.infer<typeof ReopenTimesheetPeriodSummaryInputSchema>;

export const GeneratePayrollTimeInputInputSchema = z.object({
  periodId: z.string().uuid(),
  employeeId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type GeneratePayrollTimeInputInput = z.infer<typeof GeneratePayrollTimeInputInputSchema>;

export const GeneratePayrollTimeInputsForPeriodInputSchema = z.object({
  periodId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type GeneratePayrollTimeInputsForPeriodInput = z.infer<typeof GeneratePayrollTimeInputsForPeriodInputSchema>;

export const CreateOvertimePolicyInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateOvertimePolicyInput = z.infer<typeof CreateOvertimePolicyInputSchema>;

export const CreateOvertimePolicyVersionInputSchema = z.object({
  policyId: z.string().uuid(),
  roundingIncrementMinutes: z.number().int().min(1).max(60),
  roundingMode: RoundingModeSchema,
  minOvertimeMinutes: z.number().int().min(0),
  dailyOvertimeCapMinutes: z.number().int().positive().nullable(),
  weeklyOvertimeCapMinutes: z.number().int().positive().nullable(),
  standardWorkdayMinutes: z.number().int().positive().max(1440),
  defaultBreakDeductionMinutes: z.number().int().min(0),
  requiresPreApproval: z.boolean(),
  effectiveFrom: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateOvertimePolicyVersionInput = z.infer<typeof CreateOvertimePolicyVersionInputSchema>;

export const PublishOvertimePolicyVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishOvertimePolicyVersionInput = z.infer<typeof PublishOvertimePolicyVersionInputSchema>;
