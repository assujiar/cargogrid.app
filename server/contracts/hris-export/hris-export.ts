/**
 * HRIS bulk-export contracts (ISS-2026-075). One module for all four export RPCs
 * -- `app.export_attendance_sessions` (HRT-278), `app.export_schedule_assignments`
 * (HRT-279), `app.export_leave_requests` (HRT-280) and `app.export_timesheet_entries`
 * (HRT-281) -- deliberately, and the reason is the entry's own.
 *
 * `ISS-2026-075` was filed against the timesheet export alone and immediately corrected
 * its own severity: all four sibling exports had identically zero TypeScript wrapper,
 * so wiring one "would create a new, arbitrary inconsistency across this phase rather
 * than resolve one." That correction is what makes a shared module the right shape here
 * rather than four per-capability files: the four RPCs take the SAME four parameters,
 * enforce the SAME `HRS:Export` gate, cap at the SAME 366 days, and write the SAME
 * audit event. Four copies of that would be four places for it to drift.
 *
 * Each capability keeps its own row schema, because the columns genuinely differ.
 */

import { z } from "zod";

/**
 * Every one of the four RPCs raises `invalid_date_range` past this. Mirrored here so
 * the form can refuse before a round trip, never INSTEAD of the server check.
 */
export const HRIS_EXPORT_MAX_RANGE_DAYS = 366;

const DateString = z.string();

export const AttendanceSessionExportRowSchema = z.object({
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: DateString,
  status: z.string(),
  effectiveClockInAt: z.string().nullable(),
  effectiveClockOutAt: z.string().nullable(),
  payrollInputStatus: z.string().nullable(),
  exceptionTypes: z.string().nullable(),
});
export type AttendanceSessionExportRow = z.infer<typeof AttendanceSessionExportRowSchema>;

export function parseAttendanceSessionExportRow(row: Record<string, unknown>): AttendanceSessionExportRow {
  return AttendanceSessionExportRowSchema.parse({
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    status: row.status,
    effectiveClockInAt: row.effective_clock_in_at ?? null,
    effectiveClockOutAt: row.effective_clock_out_at ?? null,
    payrollInputStatus: row.payroll_input_status ?? null,
    exceptionTypes: row.exception_types ?? null,
  });
}

export const ScheduleAssignmentExportRowSchema = z.object({
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: DateString,
  shiftTemplateName: z.string(),
  status: z.string(),
});
export type ScheduleAssignmentExportRow = z.infer<typeof ScheduleAssignmentExportRowSchema>;

export function parseScheduleAssignmentExportRow(row: Record<string, unknown>): ScheduleAssignmentExportRow {
  return ScheduleAssignmentExportRowSchema.parse({
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    shiftTemplateName: row.shift_template_name,
    status: row.status,
  });
}

/**
 * The leave RPC names its first two columns `employee_code`/`employee_name`, where the
 * other three use `employee_number`/`employee_full_name`. Normalised to the common
 * shape here -- at the one place that reads the raw column names -- rather than leaking
 * that inconsistency into four call sites and a CSV header.
 */
export const LeaveRequestExportRowSchema = z.object({
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  leaveTypeCode: z.string(),
  category: z.string(),
  dateFrom: DateString,
  dateTo: DateString,
  totalUnits: z.coerce.number(),
  status: z.string(),
});
export type LeaveRequestExportRow = z.infer<typeof LeaveRequestExportRowSchema>;

export function parseLeaveRequestExportRow(row: Record<string, unknown>): LeaveRequestExportRow {
  return LeaveRequestExportRowSchema.parse({
    employeeNumber: row.employee_code,
    employeeFullName: row.employee_name,
    leaveTypeCode: row.leave_type_code,
    category: row.category,
    dateFrom: row.date_from,
    dateTo: row.date_to,
    totalUnits: row.total_units,
    status: row.status,
  });
}

export const TimesheetEntryExportRowSchema = z.object({
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: DateString,
  jobNumber: z.string().nullable(),
  shipmentNumber: z.string().nullable(),
  entryMinutes: z.number().int(),
  eligibleMinutes: z.number().int(),
  approvedMinutes: z.number().int().nullable(),
  status: z.string(),
});
export type TimesheetEntryExportRow = z.infer<typeof TimesheetEntryExportRowSchema>;

export function parseTimesheetEntryExportRow(row: Record<string, unknown>): TimesheetEntryExportRow {
  return TimesheetEntryExportRowSchema.parse({
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    jobNumber: row.job_number ?? null,
    shipmentNumber: row.shipment_number ?? null,
    entryMinutes: row.entry_minutes,
    eligibleMinutes: row.eligible_minutes,
    approvedMinutes: row.approved_minutes ?? null,
    status: row.status,
  });
}

// --- CSV headers, one per export ------------------------------------------
//
// Kept beside the row schemas rather than in the UI, so a column added to an RPC's
// projection has exactly one place where the header and the row mapping can be updated
// together. A header that has drifted from its rows is a silently mislabelled
// spreadsheet, which is worse than a missing column.

export const SCHEDULE_ASSIGNMENT_EXPORT_HEADER = ["Employee number", "Employee", "Work date", "Shift template", "Status"] as const;
export const ATTENDANCE_SESSION_EXPORT_HEADER = ["Employee number", "Employee", "Work date", "Status", "Clock in", "Clock out", "Payroll input status", "Exceptions"] as const;
export const LEAVE_REQUEST_EXPORT_HEADER = ["Employee number", "Employee", "Leave type", "Category", "From", "To", "Total units", "Status"] as const;
export const TIMESHEET_ENTRY_EXPORT_HEADER = ["Employee number", "Employee", "Work date", "Job", "Shipment", "Entry minutes", "Eligible minutes", "Approved minutes", "Status"] as const;

export function attendanceSessionExportCells(row: AttendanceSessionExportRow): readonly (string | number | null)[] {
  return [row.employeeNumber, row.employeeFullName, row.workDate, row.status, row.effectiveClockInAt, row.effectiveClockOutAt, row.payrollInputStatus, row.exceptionTypes];
}

export function scheduleAssignmentExportCells(row: ScheduleAssignmentExportRow): readonly (string | number | null)[] {
  return [row.employeeNumber, row.employeeFullName, row.workDate, row.shiftTemplateName, row.status];
}

export function leaveRequestExportCells(row: LeaveRequestExportRow): readonly (string | number | null)[] {
  return [row.employeeNumber, row.employeeFullName, row.leaveTypeCode, row.category, row.dateFrom, row.dateTo, row.totalUnits, row.status];
}

export function timesheetEntryExportCells(row: TimesheetEntryExportRow): readonly (string | number | null)[] {
  return [row.employeeNumber, row.employeeFullName, row.workDate, row.jobNumber, row.shipmentNumber, row.entryMinutes, row.eligibleMinutes, row.approvedMinutes, row.status];
}
