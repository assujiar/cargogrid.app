/**
 * Shift, Roster and Scheduling contract (HRT-279, CG-S12-HRT-007). Mirrors
 * supabase/migrations/20260730910000_create_hris_shift_roster_scheduling.sql's
 * shift template/version/segment, roster cycle/slot, schedule assignment,
 * coverage requirement, and swap request shapes and their RPCs. Follows the
 * exact directory convention HRT-274..278 established: Zod schemas here,
 * list/read projections in server/queries/shift-roster.ts, RPC-calling
 * mutation wrappers with an enumerated error-code type in
 * server/mutations/shift-roster.ts.
 */

import { z } from "zod";

export const SHIFT_TEMPLATE_STATUSES = ["draft", "published", "archived"] as const;
export const ShiftTemplateStatusSchema = z.enum(SHIFT_TEMPLATE_STATUSES);
export type ShiftTemplateStatus = z.infer<typeof ShiftTemplateStatusSchema>;

export const SHIFT_TEMPLATE_VERSION_STATUSES = ["draft", "published", "superseded"] as const;
export const ShiftTemplateVersionStatusSchema = z.enum(SHIFT_TEMPLATE_VERSION_STATUSES);
export type ShiftTemplateVersionStatus = z.infer<typeof ShiftTemplateVersionStatusSchema>;

export const SHIFT_TYPES = ["fixed", "flexible", "split"] as const;
export const ShiftTypeSchema = z.enum(SHIFT_TYPES);
export type ShiftType = z.infer<typeof ShiftTypeSchema>;

export const SEGMENT_TYPES = ["work", "break"] as const;
export const SegmentTypeSchema = z.enum(SEGMENT_TYPES);
export type SegmentType = z.infer<typeof SegmentTypeSchema>;

export const ROSTER_CYCLE_STATUSES = ["draft", "published", "archived"] as const;
export const RosterCycleStatusSchema = z.enum(ROSTER_CYCLE_STATUSES);
export type RosterCycleStatus = z.infer<typeof RosterCycleStatusSchema>;

export const SCHEDULE_ASSIGNMENT_STATUSES = ["scheduled", "published", "cancelled", "superseded"] as const;
export const ScheduleAssignmentStatusSchema = z.enum(SCHEDULE_ASSIGNMENT_STATUSES);
export type ScheduleAssignmentStatus = z.infer<typeof ScheduleAssignmentStatusSchema>;

export const SCHEDULE_ASSIGNMENT_SOURCES = ["manual", "bulk_generated", "swap"] as const;
export const ScheduleAssignmentSourceSchema = z.enum(SCHEDULE_ASSIGNMENT_SOURCES);
export type ScheduleAssignmentSource = z.infer<typeof ScheduleAssignmentSourceSchema>;

export const SWAP_STATUSES = ["pending_approval", "approved", "rejected", "cancelled"] as const;
export const SwapStatusSchema = z.enum(SWAP_STATUSES);
export type SwapStatus = z.infer<typeof SwapStatusSchema>;

export const SWAP_DECISIONS = ["approve", "reject"] as const;
export const SwapDecisionSchema = z.enum(SWAP_DECISIONS);
export type SwapDecision = z.infer<typeof SwapDecisionSchema>;

export const COVERAGE_STATUSES = ["met", "below_minimum"] as const;
export const CoverageStatusSchema = z.enum(COVERAGE_STATUSES);
export type CoverageStatus = z.infer<typeof CoverageStatusSchema>;

// --- Segment (input shape -- matches app.create_shift_template_version's own
// p_segments jsonb array shape exactly) ---

export const ShiftSegmentInputSchema = z.object({
  segmentType: SegmentTypeSchema,
  startTime: z.string().min(1),
  endTime: z.string().min(1),
});
export type ShiftSegmentInput = z.infer<typeof ShiftSegmentInputSchema>;

export const ShiftSegmentRowSchema = z.object({
  sequenceNumber: z.number().int().nonnegative(),
  segmentType: SegmentTypeSchema,
  startTime: z.string(),
  endTime: z.string(),
  crossesMidnight: z.boolean(),
  durationMinutes: z.number().int().positive(),
});
export type ShiftSegmentRow = z.infer<typeof ShiftSegmentRowSchema>;

function parseShiftSegmentRow(row: Record<string, unknown>): ShiftSegmentRow {
  return ShiftSegmentRowSchema.parse({
    sequenceNumber: row.sequence_number,
    segmentType: row.segment_type,
    startTime: row.start_time,
    endTime: row.end_time,
    crossesMidnight: row.crosses_midnight,
    durationMinutes: row.duration_minutes,
  });
}

// --- Core rows ---

export const ShiftTemplateRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  code: z.string(),
  name: z.string(),
  status: ShiftTemplateStatusSchema,
  publishedVersionId: z.string().uuid().nullable(),
  publishedVersionNumber: z.number().int().nullable(),
  recordVersion: z.number().int().positive(),
});
export type ShiftTemplateRow = z.infer<typeof ShiftTemplateRowSchema>;

export function parseShiftTemplateRow(row: Record<string, unknown>): ShiftTemplateRow {
  return ShiftTemplateRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id ?? null,
    code: row.code,
    name: row.name,
    status: row.status,
    publishedVersionId: row.published_version_id ?? null,
    publishedVersionNumber: row.published_version_number ?? null,
    recordVersion: row.record_version,
  });
}

export const ShiftTemplateVersionDetailSchema = z.object({
  id: z.string().uuid(),
  shiftTemplateId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: ShiftTemplateVersionStatusSchema,
  effectiveFrom: z.string(),
  timezone: z.string(),
  dayBoundaryLocalTime: z.string(),
  shiftType: ShiftTypeSchema,
  graceLateMinutes: z.number().int().nullable(),
  graceEarlyMinutes: z.number().int().nullable(),
  crossesMidnight: z.boolean(),
  totalWorkMinutes: z.number().int().positive(),
  totalBreakMinutes: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
  segments: z.array(ShiftSegmentRowSchema),
});
export type ShiftTemplateVersionDetail = z.infer<typeof ShiftTemplateVersionDetailSchema>;

export function parseShiftTemplateVersionDetail(row: Record<string, unknown>): ShiftTemplateVersionDetail {
  const rawSegments = Array.isArray(row.segments) ? (row.segments as Record<string, unknown>[]) : [];
  return ShiftTemplateVersionDetailSchema.parse({
    id: row.id,
    shiftTemplateId: row.shift_template_id,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: row.effective_from,
    timezone: row.timezone,
    dayBoundaryLocalTime: row.day_boundary_local_time,
    shiftType: row.shift_type,
    graceLateMinutes: row.grace_late_minutes ?? null,
    graceEarlyMinutes: row.grace_early_minutes ?? null,
    crossesMidnight: row.crosses_midnight,
    totalWorkMinutes: row.total_work_minutes,
    totalBreakMinutes: row.total_break_minutes,
    recordVersion: row.record_version,
    segments: rawSegments.map(parseShiftSegmentRow),
  });
}

export const RosterCycleRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string(),
  cycleLengthDays: z.number().int().positive(),
  status: RosterCycleStatusSchema,
  slotCount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
});
export type RosterCycleRow = z.infer<typeof RosterCycleRowSchema>;

export function parseRosterCycleRow(row: Record<string, unknown>): RosterCycleRow {
  return RosterCycleRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id ?? null,
    name: row.name,
    cycleLengthDays: row.cycle_length_days,
    status: row.status,
    slotCount: row.slot_count ?? 0,
    recordVersion: row.record_version,
  });
}

export const RosterCycleSlotRowSchema = z.object({
  dayOffset: z.number().int().nonnegative(),
  shiftTemplateId: z.string().uuid().nullable(),
});
export type RosterCycleSlotRow = z.infer<typeof RosterCycleSlotRowSchema>;

export const RosterCycleDetailSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string(),
  cycleLengthDays: z.number().int().positive(),
  status: RosterCycleStatusSchema,
  recordVersion: z.number().int().positive(),
  slots: z.array(RosterCycleSlotRowSchema),
});
export type RosterCycleDetail = z.infer<typeof RosterCycleDetailSchema>;

export function parseRosterCycleDetail(row: Record<string, unknown>): RosterCycleDetail {
  const rawSlots = Array.isArray(row.slots) ? (row.slots as Record<string, unknown>[]) : [];
  return RosterCycleDetailSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id ?? null,
    name: row.name,
    cycleLengthDays: row.cycle_length_days,
    status: row.status,
    recordVersion: row.record_version,
    slots: rawSlots.map((s) => ({ dayOffset: s.day_offset, shiftTemplateId: s.shift_template_id ?? null })),
  });
}

export const RosterHolidayRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  holidayDate: z.string(),
  name: z.string(),
  isWorkingDay: z.boolean(),
  recordVersion: z.number().int().positive(),
});
export type RosterHolidayRow = z.infer<typeof RosterHolidayRowSchema>;

export function parseRosterHolidayRow(row: Record<string, unknown>): RosterHolidayRow {
  return RosterHolidayRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id ?? null,
    holidayDate: row.holiday_date,
    name: row.name,
    isWorkingDay: row.is_working_day,
    recordVersion: row.record_version,
  });
}

export const CoverageRequirementRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid(),
  shiftTemplateId: z.string().uuid(),
  shiftTemplateName: z.string(),
  dayOfWeek: z.number().int().min(0).max(6),
  minHeadcount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
});
export type CoverageRequirementRow = z.infer<typeof CoverageRequirementRowSchema>;

export function parseCoverageRequirementRow(row: Record<string, unknown>): CoverageRequirementRow {
  return CoverageRequirementRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id,
    shiftTemplateId: row.shift_template_id,
    shiftTemplateName: row.shift_template_name,
    dayOfWeek: row.day_of_week,
    minHeadcount: row.min_headcount,
    recordVersion: row.record_version,
  });
}

export const CoveragePreviewRowSchema = z.object({
  workDate: z.string(),
  shiftTemplateId: z.string().uuid(),
  shiftTemplateName: z.string(),
  scheduledCount: z.number().int().nonnegative(),
  minHeadcount: z.number().int().nonnegative(),
  coverageStatus: CoverageStatusSchema,
});
export type CoveragePreviewRow = z.infer<typeof CoveragePreviewRowSchema>;

export function parseCoveragePreviewRow(row: Record<string, unknown>): CoveragePreviewRow {
  return CoveragePreviewRowSchema.parse({
    workDate: row.work_date,
    shiftTemplateId: row.shift_template_id,
    shiftTemplateName: row.shift_template_name,
    scheduledCount: row.scheduled_count,
    minHeadcount: row.min_headcount,
    coverageStatus: row.coverage_status,
  });
}

export const MyScheduleRowSchema = z.object({
  assignmentId: z.string().uuid(),
  workDate: z.string(),
  shiftTemplateId: z.string().uuid(),
  shiftTemplateName: z.string(),
  shiftType: ShiftTypeSchema,
  crossesMidnight: z.boolean(),
  status: ScheduleAssignmentStatusSchema,
});
export type MyScheduleRow = z.infer<typeof MyScheduleRowSchema>;

export function parseMyScheduleRow(row: Record<string, unknown>): MyScheduleRow {
  return MyScheduleRowSchema.parse({
    assignmentId: row.assignment_id,
    workDate: row.work_date,
    shiftTemplateId: row.shift_template_id,
    shiftTemplateName: row.shift_template_name,
    shiftType: row.shift_type,
    crossesMidnight: row.crosses_midnight,
    status: row.status,
  });
}

export const ScheduleAssignmentListRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: z.string(),
  shiftTemplateName: z.string(),
  status: ScheduleAssignmentStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type ScheduleAssignmentListRow = z.infer<typeof ScheduleAssignmentListRowSchema>;

export function parseScheduleAssignmentListRow(row: Record<string, unknown>): ScheduleAssignmentListRow {
  return ScheduleAssignmentListRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    shiftTemplateName: row.shift_template_name,
    status: row.status,
    recordVersion: row.record_version,
  });
}

export const ScheduleAssignmentDetailSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  workDate: z.string(),
  shiftTemplateVersionId: z.string().uuid(),
  shiftTemplateName: z.string(),
  status: ScheduleAssignmentStatusSchema,
  source: ScheduleAssignmentSourceSchema,
  recordVersion: z.number().int().positive(),
});
export type ScheduleAssignmentDetail = z.infer<typeof ScheduleAssignmentDetailSchema>;

export function parseScheduleAssignmentDetail(row: Record<string, unknown>): ScheduleAssignmentDetail {
  return ScheduleAssignmentDetailSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    workDate: row.work_date,
    shiftTemplateVersionId: row.shift_template_version_id,
    shiftTemplateName: row.shift_template_name,
    status: row.status,
    source: row.source,
    recordVersion: row.record_version,
  });
}

export const SwapRequestRowSchema = z.object({
  id: z.string().uuid(),
  requestingEmployeeId: z.string().uuid(),
  requestingEmployeeNumber: z.string(),
  targetEmployeeId: z.string().uuid(),
  targetEmployeeNumber: z.string(),
  assignmentId: z.string().uuid(),
  targetAssignmentId: z.string().uuid(),
  status: SwapStatusSchema,
  createdAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type SwapRequestRow = z.infer<typeof SwapRequestRowSchema>;

export function parseSwapRequestRow(row: Record<string, unknown>): SwapRequestRow {
  return SwapRequestRowSchema.parse({
    id: row.id,
    requestingEmployeeId: row.requesting_employee_id,
    requestingEmployeeNumber: row.requesting_employee_number,
    targetEmployeeId: row.target_employee_id,
    targetEmployeeNumber: row.target_employee_number,
    assignmentId: row.assignment_id,
    targetAssignmentId: row.target_assignment_id,
    status: row.status,
    createdAt: row.created_at,
    recordVersion: row.record_version,
  });
}

export const MySwapRequestRowSchema = z.object({
  id: z.string().uuid(),
  role: z.enum(["requester", "target"]),
  assignmentId: z.string().uuid(),
  targetAssignmentId: z.string().uuid(),
  status: SwapStatusSchema,
  createdAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type MySwapRequestRow = z.infer<typeof MySwapRequestRowSchema>;

export function parseMySwapRequestRow(row: Record<string, unknown>): MySwapRequestRow {
  return MySwapRequestRowSchema.parse({
    id: row.id,
    role: row.role,
    assignmentId: row.assignment_id,
    targetAssignmentId: row.target_assignment_id,
    status: row.status,
    createdAt: row.created_at,
    recordVersion: row.record_version,
  });
}

export const PublishScheduleAssignmentsResultRowSchema = z.object({
  assignmentId: z.string().uuid(),
  published: z.boolean(),
  skipReason: z.string().nullable(),
});
export type PublishScheduleAssignmentsResultRow = z.infer<typeof PublishScheduleAssignmentsResultRowSchema>;

export function parsePublishScheduleAssignmentsResultRow(row: Record<string, unknown>): PublishScheduleAssignmentsResultRow {
  return PublishScheduleAssignmentsResultRowSchema.parse({
    assignmentId: row.assignment_id,
    published: row.published,
    skipReason: row.skip_reason ?? null,
  });
}

export const GenerateRosterScheduleAssignmentsResultSchema = z.object({
  createdCount: z.number().int().nonnegative(),
  supersededCount: z.number().int().nonnegative(),
  skippedCount: z.number().int().nonnegative(),
  jobId: z.string().uuid(),
});
export type GenerateRosterScheduleAssignmentsResult = z.infer<typeof GenerateRosterScheduleAssignmentsResultSchema>;

export function parseGenerateRosterScheduleAssignmentsResult(row: Record<string, unknown>): GenerateRosterScheduleAssignmentsResult {
  return GenerateRosterScheduleAssignmentsResultSchema.parse({
    createdCount: row.created_count,
    supersededCount: row.superseded_count,
    skippedCount: row.skipped_count,
    jobId: row.job_id,
  });
}

// --- Mutation inputs ---

export const CreateShiftTemplateInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  code: z.string().min(1),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateShiftTemplateInput = z.infer<typeof CreateShiftTemplateInputSchema>;

export const CreateShiftTemplateVersionInputSchema = z.object({
  shiftTemplateId: z.string().uuid(),
  timezone: z.string().min(1),
  dayBoundaryLocalTime: z.string().min(1).nullable(),
  shiftType: ShiftTypeSchema,
  graceLateMinutes: z.number().int().min(0).max(240).nullable(),
  graceEarlyMinutes: z.number().int().min(0).max(240).nullable(),
  effectiveFrom: z.string().min(1),
  segments: z.array(ShiftSegmentInputSchema).min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateShiftTemplateVersionInput = z.infer<typeof CreateShiftTemplateVersionInputSchema>;

export const PublishShiftTemplateVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishShiftTemplateVersionInput = z.infer<typeof PublishShiftTemplateVersionInputSchema>;

export const CreateRosterCycleInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string().min(1),
  cycleLengthDays: z.number().int().min(1).max(60),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateRosterCycleInput = z.infer<typeof CreateRosterCycleInputSchema>;

export const SetRosterCycleSlotInputSchema = z.object({
  rosterCycleId: z.string().uuid(),
  dayOffset: z.number().int().nonnegative(),
  shiftTemplateId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetRosterCycleSlotInput = z.infer<typeof SetRosterCycleSlotInputSchema>;

export const PublishRosterCycleInputSchema = z.object({
  rosterCycleId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishRosterCycleInput = z.infer<typeof PublishRosterCycleInputSchema>;

export const SetRosterHolidayInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  holidayDate: z.string().min(1),
  name: z.string().min(1),
  isWorkingDay: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetRosterHolidayInput = z.infer<typeof SetRosterHolidayInputSchema>;

export const RemoveRosterHolidayInputSchema = z.object({
  holidayId: z.string().uuid(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveRosterHolidayInput = z.infer<typeof RemoveRosterHolidayInputSchema>;

export const SetScheduleCoverageRequirementInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid(),
  shiftTemplateId: z.string().uuid(),
  dayOfWeek: z.number().int().min(0).max(6),
  minHeadcount: z.number().int().nonnegative(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type SetScheduleCoverageRequirementInput = z.infer<typeof SetScheduleCoverageRequirementInputSchema>;

export const AssignEmployeeScheduleInputSchema = z.object({
  tenantId: z.string().uuid(),
  employeeId: z.string().uuid(),
  shiftTemplateVersionId: z.string().uuid(),
  workDate: z.string().min(1),
  source: ScheduleAssignmentSourceSchema,
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AssignEmployeeScheduleInput = z.infer<typeof AssignEmployeeScheduleInputSchema>;

export const CancelScheduleAssignmentInputSchema = z.object({
  assignmentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelScheduleAssignmentInput = z.infer<typeof CancelScheduleAssignmentInputSchema>;

export const PublishScheduleAssignmentsInputSchema = z.object({
  tenantId: z.string().uuid(),
  fromDate: z.string().min(1),
  toDate: z.string().min(1),
  orgUnitId: z.string().uuid().nullable(),
  employeeId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishScheduleAssignmentsInput = z.infer<typeof PublishScheduleAssignmentsInputSchema>;

export const GenerateRosterScheduleAssignmentsInputSchema = z.object({
  tenantId: z.string().uuid(),
  rosterCycleId: z.string().uuid(),
  employeeIds: z.array(z.string().uuid()).min(1),
  fromDate: z.string().min(1),
  toDate: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type GenerateRosterScheduleAssignmentsInput = z.infer<typeof GenerateRosterScheduleAssignmentsInputSchema>;

export const RequestScheduleSwapInputSchema = z.object({
  assignmentId: z.string().uuid(),
  targetEmployeeId: z.string().uuid(),
  targetAssignmentId: z.string().uuid(),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RequestScheduleSwapInput = z.infer<typeof RequestScheduleSwapInputSchema>;

export const DecideScheduleSwapRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: SwapDecisionSchema,
  decidedReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideScheduleSwapRequestInput = z.infer<typeof DecideScheduleSwapRequestInputSchema>;

export const CancelScheduleSwapRequestInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelScheduleSwapRequestInput = z.infer<typeof CancelScheduleSwapRequestInputSchema>;
