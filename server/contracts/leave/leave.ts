/**
 * Leave, Permit and Business Trip contract (HRT-280, CG-S12-HRT-008). Mirrors
 * supabase/migrations/20260730930000_create_hris_leave_permit_business_trip.sql's
 * type/policy-version/balance-ledger/request shapes and their RPCs. Follows the
 * exact directory convention HRT-274..279 established: Zod schemas here,
 * list/read projections in server/queries/leave.ts, RPC-calling mutation
 * wrappers with an enumerated error-code type in server/mutations/leave.ts.
 */

import { z } from "zod";

export const LEAVE_CATEGORIES = ["leave", "permit", "business_trip"] as const;
export const LeaveCategorySchema = z.enum(LEAVE_CATEGORIES);
export type LeaveCategory = z.infer<typeof LeaveCategorySchema>;

export const LEAVE_TYPE_STATUSES = ["draft", "published", "archived"] as const;
export const LeaveTypeStatusSchema = z.enum(LEAVE_TYPE_STATUSES);
export type LeaveTypeStatus = z.infer<typeof LeaveTypeStatusSchema>;

export const EVIDENCE_CLASSIFICATIONS = ["none", "personal", "medical"] as const;
export const EvidenceClassificationSchema = z.enum(EVIDENCE_CLASSIFICATIONS);
export type EvidenceClassification = z.infer<typeof EvidenceClassificationSchema>;

export const POLICY_VERSION_STATUSES = ["draft", "published", "superseded"] as const;
export const PolicyVersionStatusSchema = z.enum(POLICY_VERSION_STATUSES);
export type PolicyVersionStatus = z.infer<typeof PolicyVersionStatusSchema>;

export const ACCRUAL_FREQUENCIES = ["none", "monthly", "annual"] as const;
export const AccrualFrequencySchema = z.enum(ACCRUAL_FREQUENCIES);
export type AccrualFrequency = z.infer<typeof AccrualFrequencySchema>;

export const DAY_PORTIONS = ["full_day", "half_day_morning", "half_day_afternoon"] as const;
export const DayPortionSchema = z.enum(DAY_PORTIONS);
export type DayPortion = z.infer<typeof DayPortionSchema>;

export const LEAVE_REQUEST_STATUSES = ["draft", "pending_approval", "approved", "rejected", "cancelled"] as const;
export const LeaveRequestStatusSchema = z.enum(LEAVE_REQUEST_STATUSES);
export type LeaveRequestStatus = z.infer<typeof LeaveRequestStatusSchema>;

export const PAYROLL_INPUT_STATUSES = ["pending", "approved"] as const;
export const PayrollInputStatusSchema = z.enum(PAYROLL_INPUT_STATUSES);
export type PayrollInputStatus = z.infer<typeof PayrollInputStatusSchema>;

export const APPROVAL_DECISIONS = ["approved", "rejected"] as const;
export const ApprovalDecisionSchema = z.enum(APPROVAL_DECISIONS);
export type ApprovalDecision = z.infer<typeof ApprovalDecisionSchema>;

export const LEDGER_EVENT_TYPES = [
  "accrual",
  "carry_forward_expire",
  "adjustment",
  "opening_balance",
  "request_debit",
  "request_credit_reversal",
] as const;
export const LedgerEventTypeSchema = z.enum(LEDGER_EVENT_TYPES);
export type LedgerEventType = z.infer<typeof LedgerEventTypeSchema>;

// --- Core rows ---

export const LeaveTypeRowSchema = z.object({
  id: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  category: LeaveCategorySchema,
  requiresBalance: z.boolean(),
  requiresEvidence: z.boolean(),
  evidenceClassification: EvidenceClassificationSchema,
  status: LeaveTypeStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type LeaveTypeRow = z.infer<typeof LeaveTypeRowSchema>;

export function parseLeaveTypeRow(row: Record<string, unknown>): LeaveTypeRow {
  return LeaveTypeRowSchema.parse({
    id: row.id,
    code: row.code,
    name: row.name,
    category: row.category,
    requiresBalance: row.requires_balance,
    requiresEvidence: row.requires_evidence,
    evidenceClassification: row.evidence_classification,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const LeaveTypePolicyVersionSchema = z.object({
  id: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  versionNumber: z.number().int().positive(),
  status: PolicyVersionStatusSchema,
  effectiveFrom: z.string(),
  accrualFrequency: AccrualFrequencySchema,
  accrualAmountPerPeriod: z.number().nonnegative(),
  accrualMaxBalance: z.number().nullable(),
  carryForwardMaxUnits: z.number().nonnegative(),
  minNoticeDays: z.number().int().nonnegative(),
  maxConsecutiveUnits: z.number().nullable(),
  eligibilityMinTenureDays: z.number().int().nonnegative(),
  negativeBalanceAllowed: z.boolean(),
  recordVersion: z.number().int().positive(),
});
export type LeaveTypePolicyVersion = z.infer<typeof LeaveTypePolicyVersionSchema>;

export function parseLeaveTypePolicyVersion(row: Record<string, unknown>): LeaveTypePolicyVersion {
  return LeaveTypePolicyVersionSchema.parse({
    id: row.id,
    leaveTypeId: row.leave_type_id,
    orgUnitId: row.org_unit_id ?? null,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: row.effective_from,
    accrualFrequency: row.accrual_frequency,
    accrualAmountPerPeriod: Number(row.accrual_amount_per_period),
    accrualMaxBalance: row.accrual_max_balance === null || row.accrual_max_balance === undefined ? null : Number(row.accrual_max_balance),
    carryForwardMaxUnits: Number(row.carry_forward_max_units),
    minNoticeDays: row.min_notice_days,
    maxConsecutiveUnits: row.max_consecutive_units === null || row.max_consecutive_units === undefined ? null : Number(row.max_consecutive_units),
    eligibilityMinTenureDays: row.eligibility_min_tenure_days,
    negativeBalanceAllowed: row.negative_balance_allowed,
    recordVersion: row.record_version,
  });
}

export const EmployeeLeaveBalanceRowSchema = z.object({
  leaveTypeId: z.string().uuid(),
  code: z.string(),
  name: z.string(),
  category: LeaveCategorySchema,
  requiresBalance: z.boolean(),
  balance: z.number(),
  pendingUnits: z.number(),
});
export type EmployeeLeaveBalanceRow = z.infer<typeof EmployeeLeaveBalanceRowSchema>;

export function parseEmployeeLeaveBalanceRow(row: Record<string, unknown>): EmployeeLeaveBalanceRow {
  return EmployeeLeaveBalanceRowSchema.parse({
    leaveTypeId: row.leave_type_id,
    code: row.code,
    name: row.name,
    category: row.category,
    requiresBalance: row.requires_balance,
    balance: Number(row.balance),
    pendingUnits: Number(row.pending_units),
  });
}

export const LeaveRequestListRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  leaveTypeId: z.string().uuid(),
  leaveTypeCode: z.string(),
  category: LeaveCategorySchema,
  status: LeaveRequestStatusSchema,
  dateFrom: z.string(),
  dateTo: z.string(),
  dayPortion: DayPortionSchema,
  totalUnits: z.number(),
  payrollInputStatus: PayrollInputStatusSchema,
  recordVersion: z.number().int().positive(),
  reasonVisible: z.boolean(),
  reason: z.string().nullable(),
});
export type LeaveRequestListRow = z.infer<typeof LeaveRequestListRowSchema>;

export function parseLeaveRequestListRow(row: Record<string, unknown>): LeaveRequestListRow {
  return LeaveRequestListRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    leaveTypeId: row.leave_type_id,
    leaveTypeCode: row.leave_type_code,
    category: row.category,
    status: row.status,
    dateFrom: row.date_from,
    dateTo: row.date_to,
    dayPortion: row.day_portion,
    totalUnits: Number(row.total_units),
    payrollInputStatus: row.payroll_input_status,
    recordVersion: row.record_version,
    reasonVisible: row.reason_visible,
    reason: row.reason ?? null,
  });
}

export const LeaveRequestDetailSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  status: LeaveRequestStatusSchema,
  dateFrom: z.string(),
  dateTo: z.string(),
  dayPortion: DayPortionSchema,
  totalUnits: z.number(),
  reason: z.string().nullable(),
  destination: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  scheduleSnapshot: z.array(z.record(z.string(), z.unknown())),
  payrollInputStatus: PayrollInputStatusSchema,
  decidedReason: z.string().nullable(),
  cancelReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type LeaveRequestDetail = z.infer<typeof LeaveRequestDetailSchema>;

export function parseLeaveRequestDetail(row: Record<string, unknown>): LeaveRequestDetail {
  return LeaveRequestDetailSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    leaveTypeId: row.leave_type_id,
    status: row.status,
    dateFrom: row.date_from,
    dateTo: row.date_to,
    dayPortion: row.day_portion,
    totalUnits: Number(row.total_units),
    reason: row.reason ?? null,
    destination: row.destination ?? null,
    evidenceFileId: row.evidence_file_id ?? null,
    scheduleSnapshot: Array.isArray(row.schedule_snapshot) ? (row.schedule_snapshot as Record<string, unknown>[]) : [],
    payrollInputStatus: row.payroll_input_status,
    decidedReason: row.decided_reason ?? null,
    cancelReason: row.cancel_reason ?? null,
    recordVersion: row.record_version,
  });
}

export const LeaveBalanceLedgerRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  eventType: LedgerEventTypeSchema,
  units: z.number(),
  effectiveDate: z.string(),
  sourceRequestId: z.string().uuid().nullable(),
  createdAt: z.string(),
});
export type LeaveBalanceLedgerRow = z.infer<typeof LeaveBalanceLedgerRowSchema>;

export function parseLeaveBalanceLedgerRow(row: Record<string, unknown>): LeaveBalanceLedgerRow {
  return LeaveBalanceLedgerRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    leaveTypeId: row.leave_type_id,
    eventType: row.event_type,
    units: Number(row.units),
    effectiveDate: row.effective_date,
    sourceRequestId: row.source_request_id ?? null,
    createdAt: row.created_at,
  });
}

export const LeaveCalendarRowSchema = z.object({
  employeeId: z.string().uuid(),
  employeeName: z.string(),
  leaveTypeId: z.string().uuid(),
  category: LeaveCategorySchema,
  dateFrom: z.string(),
  dateTo: z.string(),
  dayPortion: DayPortionSchema,
});
export type LeaveCalendarRow = z.infer<typeof LeaveCalendarRowSchema>;

export function parseLeaveCalendarRow(row: Record<string, unknown>): LeaveCalendarRow {
  return LeaveCalendarRowSchema.parse({
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    leaveTypeId: row.leave_type_id,
    category: row.category,
    dateFrom: row.date_from,
    dateTo: row.date_to,
    dayPortion: row.day_portion,
  });
}

// --- Mutation inputs ---

export const CreateLeaveTypeInputSchema = z.object({
  tenantId: z.string().uuid(),
  code: z.string().min(2).max(40),
  name: z.string().min(1),
  category: LeaveCategorySchema,
  requiresBalance: z.boolean(),
  requiresEvidence: z.boolean(),
  evidenceClassification: EvidenceClassificationSchema,
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateLeaveTypeInput = z.infer<typeof CreateLeaveTypeInputSchema>;

export const PublishLeaveTypeInputSchema = z.object({
  leaveTypeId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishLeaveTypeInput = z.infer<typeof PublishLeaveTypeInputSchema>;

export const CreateLeaveTypePolicyVersionInputSchema = z.object({
  leaveTypeId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  effectiveFrom: z.string().min(1),
  accrualFrequency: AccrualFrequencySchema,
  accrualAmountPerPeriod: z.number().nonnegative(),
  accrualMaxBalance: z.number().nonnegative().nullable(),
  carryForwardMaxUnits: z.number().nonnegative(),
  minNoticeDays: z.number().int().min(0).max(365),
  maxConsecutiveUnits: z.number().positive().nullable(),
  eligibilityMinTenureDays: z.number().int().nonnegative(),
  negativeBalanceAllowed: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateLeaveTypePolicyVersionInput = z.infer<typeof CreateLeaveTypePolicyVersionInputSchema>;

export const PublishLeaveTypePolicyVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishLeaveTypePolicyVersionInput = z.infer<typeof PublishLeaveTypePolicyVersionInputSchema>;

export const CreateLeaveRequestInputSchema = z.object({
  tenantId: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  dateFrom: z.string().min(1),
  dateTo: z.string().min(1),
  dayPortion: DayPortionSchema,
  reason: z.string().min(1),
  destination: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateLeaveRequestInput = z.infer<typeof CreateLeaveRequestInputSchema>;

export const CreateLeaveRequestForEmployeeInputSchema = CreateLeaveRequestInputSchema.extend({
  employeeId: z.string().uuid(),
});
export type CreateLeaveRequestForEmployeeInput = z.infer<typeof CreateLeaveRequestForEmployeeInputSchema>;

export const UpdateLeaveRequestDraftInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  dateFrom: z.string().min(1),
  dateTo: z.string().min(1),
  dayPortion: DayPortionSchema,
  reason: z.string().min(1),
  destination: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateLeaveRequestDraftInput = z.infer<typeof UpdateLeaveRequestDraftInputSchema>;

export const SubmitLeaveRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SubmitLeaveRequestInput = z.infer<typeof SubmitLeaveRequestInputSchema>;

export const DecideLeaveRequestInputSchema = z.object({
  requestStepId: z.string().uuid(),
  decision: ApprovalDecisionSchema,
  reason: z.string().min(1),
  overrideCoverage: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideLeaveRequestInput = z.infer<typeof DecideLeaveRequestInputSchema>;

export const CancelLeaveRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelLeaveRequestInput = z.infer<typeof CancelLeaveRequestInputSchema>;

export const AdjustLeaveBalanceInputSchema = z.object({
  tenantId: z.string().uuid(),
  employeeId: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  units: z.number().refine((v) => v !== 0, "units must be non-zero"),
  effectiveDate: z.string().min(1),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AdjustLeaveBalanceInput = z.infer<typeof AdjustLeaveBalanceInputSchema>;

export const LoadOpeningLeaveBalanceInputSchema = z.object({
  tenantId: z.string().uuid(),
  employeeId: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  units: z.number().positive(),
  asOfDate: z.string().min(1),
  sourceReference: z.string().min(1),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type LoadOpeningLeaveBalanceInput = z.infer<typeof LoadOpeningLeaveBalanceInputSchema>;

export const RunLeaveAccrualBatchInputSchema = z.object({
  tenantId: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  asOfDate: z.string().min(1),
  periodLabel: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RunLeaveAccrualBatchInput = z.infer<typeof RunLeaveAccrualBatchInputSchema>;

export const RunLeaveCarryForwardBatchInputSchema = z.object({
  tenantId: z.string().uuid(),
  leaveTypeId: z.string().uuid(),
  effectiveDate: z.string().min(1),
  periodLabel: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RunLeaveCarryForwardBatchInput = z.infer<typeof RunLeaveCarryForwardBatchInputSchema>;

export const CancelConflictingScheduleForLeaveInputSchema = z.object({
  leaveRequestId: z.string().uuid(),
  workDate: z.string().min(1),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelConflictingScheduleForLeaveInput = z.infer<typeof CancelConflictingScheduleForLeaveInputSchema>;

export const SyncEmployeeLeaveLifecycleStatusInputSchema = z.object({
  tenantId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SyncEmployeeLeaveLifecycleStatusInput = z.infer<typeof SyncEmployeeLeaveLifecycleStatusInputSchema>;

export const ApproveLeaveForPayrollInputInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApproveLeaveForPayrollInputInput = z.infer<typeof ApproveLeaveForPayrollInputInputSchema>;
