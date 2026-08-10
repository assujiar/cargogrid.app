/**
 * Attendance contract (HRT-278, CG-S12-HRT-006). Mirrors
 * supabase/migrations/20260730900000_create_hris_attendance.sql's policy/
 * policy-version/session/exception/correction-request shapes and their RPCs.
 * Follows the exact directory convention HRT-274/275/276/277 established: Zod
 * schemas here, list/read projections in server/queries/attendance.ts,
 * RPC-calling mutation wrappers with an enumerated error-code type in
 * server/mutations/attendance.ts.
 *
 * Decision 10 (see the migration's own header): the self-service clock RPC
 * carries no employee-id-shaped input field at all -- there is nothing here to
 * validate against spoofing because there is no such field to spoof.
 */

import { z } from "zod";

export const EVENT_TYPES = ["clock_in", "clock_out"] as const;
export const EventTypeSchema = z.enum(EVENT_TYPES);
export type EventType = z.infer<typeof EventTypeSchema>;

export const SOURCE_CHANNELS = ["mobile_web", "kiosk", "manual_hr", "device_import"] as const;
export const SourceChannelSchema = z.enum(SOURCE_CHANNELS);
export type SourceChannel = z.infer<typeof SourceChannelSchema>;

export const SELF_SERVICE_CHANNELS = ["mobile_web", "kiosk"] as const;
export const SelfServiceChannelSchema = z.enum(SELF_SERVICE_CHANNELS);
export type SelfServiceChannel = z.infer<typeof SelfServiceChannelSchema>;

export const SESSION_STATUSES = ["open", "closed"] as const;
export const SessionStatusSchema = z.enum(SESSION_STATUSES);
export type SessionStatus = z.infer<typeof SessionStatusSchema>;

export const PAYROLL_INPUT_STATUSES = ["pending", "approved"] as const;
export const PayrollInputStatusSchema = z.enum(PAYROLL_INPUT_STATUSES);
export type PayrollInputStatus = z.infer<typeof PayrollInputStatusSchema>;

export const EXCEPTION_TYPES = ["late", "early_leave", "missing_clock_out", "out_of_geofence", "impossible_ordering"] as const;
export const ExceptionTypeSchema = z.enum(EXCEPTION_TYPES);
export type ExceptionType = z.infer<typeof ExceptionTypeSchema>;

export const EXCEPTION_SEVERITIES = ["low", "medium", "high"] as const;
export const ExceptionSeveritySchema = z.enum(EXCEPTION_SEVERITIES);
export type ExceptionSeverity = z.infer<typeof ExceptionSeveritySchema>;

export const EXCEPTION_STATUSES = ["open", "acknowledged", "resolved", "waived"] as const;
export const ExceptionStatusSchema = z.enum(EXCEPTION_STATUSES);
export type ExceptionStatus = z.infer<typeof ExceptionStatusSchema>;

export const CORRECTION_REQUEST_TYPES = ["add_missing_clock_in", "add_missing_clock_out", "adjust_clock_in", "adjust_clock_out"] as const;
export const CorrectionRequestTypeSchema = z.enum(CORRECTION_REQUEST_TYPES);
export type CorrectionRequestType = z.infer<typeof CorrectionRequestTypeSchema>;

export const CORRECTION_STATUSES = ["pending_approval", "approved", "rejected", "cancelled"] as const;
export const CorrectionStatusSchema = z.enum(CORRECTION_STATUSES);
export type CorrectionStatus = z.infer<typeof CorrectionStatusSchema>;

export const CORRECTION_DECISIONS = ["approve", "reject"] as const;
export const CorrectionDecisionSchema = z.enum(CORRECTION_DECISIONS);
export type CorrectionDecision = z.infer<typeof CorrectionDecisionSchema>;

export const POLICY_STATUSES = ["draft", "published", "archived"] as const;
export const PolicyStatusSchema = z.enum(POLICY_STATUSES);
export type PolicyStatus = z.infer<typeof PolicyStatusSchema>;

export const POLICY_VERSION_STATUSES = ["draft", "published", "superseded"] as const;
export const PolicyVersionStatusSchema = z.enum(POLICY_VERSION_STATUSES);
export type PolicyVersionStatus = z.infer<typeof PolicyVersionStatusSchema>;

export const LOCATION_ENFORCEMENT_MODES = ["none", "advisory", "required"] as const;
export const LocationEnforcementModeSchema = z.enum(LOCATION_ENFORCEMENT_MODES);
export type LocationEnforcementMode = z.infer<typeof LocationEnforcementModeSchema>;

// --- GeoJSON point (RFC 7946, [longitude, latitude] axis order -- matches
// app.geojson_point_to_geography's own governed parser exactly) ---

export const GeoJsonPointSchema = z.object({
  type: z.literal("Point"),
  coordinates: z.tuple([z.number().min(-180).max(180), z.number().min(-90).max(90)]),
});
export type GeoJsonPoint = z.infer<typeof GeoJsonPointSchema>;

// --- Core rows ---

export const MyAttendanceStatusSchema = z.object({
  sessionId: z.string().uuid().nullable(),
  workDate: z.string().nullable(),
  status: SessionStatusSchema.nullable(),
  effectiveClockInAt: z.string().nullable(),
  effectiveClockOutAt: z.string().nullable(),
  openExceptionCount: z.number().int().nonnegative(),
  payrollInputStatus: PayrollInputStatusSchema.nullable(),
});
export type MyAttendanceStatus = z.infer<typeof MyAttendanceStatusSchema>;

export function parseMyAttendanceStatus(row: Record<string, unknown>): MyAttendanceStatus {
  return MyAttendanceStatusSchema.parse({
    sessionId: row.session_id ?? null,
    workDate: row.work_date ?? null,
    status: row.status ?? null,
    effectiveClockInAt: row.effective_clock_in_at ?? null,
    effectiveClockOutAt: row.effective_clock_out_at ?? null,
    openExceptionCount: row.open_exception_count ?? 0,
    payrollInputStatus: row.payroll_input_status ?? null,
  });
}

export const SessionListRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  employeeFullName: z.string(),
  workDate: z.string(),
  status: SessionStatusSchema,
  effectiveClockInAt: z.string().nullable(),
  effectiveClockOutAt: z.string().nullable(),
  payrollInputStatus: PayrollInputStatusSchema,
  openExceptionCount: z.number().int().nonnegative(),
  recordVersion: z.number().int().positive(),
});
export type SessionListRow = z.infer<typeof SessionListRowSchema>;

export function parseSessionListRow(row: Record<string, unknown>): SessionListRow {
  return SessionListRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    employeeFullName: row.employee_full_name,
    workDate: row.work_date,
    status: row.status,
    effectiveClockInAt: row.effective_clock_in_at ?? null,
    effectiveClockOutAt: row.effective_clock_out_at ?? null,
    payrollInputStatus: row.payroll_input_status,
    openExceptionCount: row.open_exception_count ?? 0,
    recordVersion: row.record_version,
  });
}

export const SessionDetailSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  workDate: z.string(),
  status: SessionStatusSchema,
  timezone: z.string(),
  effectiveClockInAt: z.string().nullable(),
  effectiveClockOutAt: z.string().nullable(),
  rawClockInAt: z.string().nullable(),
  rawClockOutAt: z.string().nullable(),
  payrollInputStatus: PayrollInputStatusSchema,
  recordVersion: z.number().int().positive(),
});
export type SessionDetail = z.infer<typeof SessionDetailSchema>;

export function parseSessionDetail(row: Record<string, unknown>): SessionDetail {
  return SessionDetailSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    workDate: row.work_date,
    status: row.status,
    timezone: row.timezone,
    effectiveClockInAt: row.effective_clock_in_at ?? null,
    effectiveClockOutAt: row.effective_clock_out_at ?? null,
    rawClockInAt: row.raw_clock_in_at ?? null,
    rawClockOutAt: row.raw_clock_out_at ?? null,
    payrollInputStatus: row.payroll_input_status,
    recordVersion: row.record_version,
  });
}

export const AttendanceExceptionRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid(),
  employeeNumber: z.string(),
  sessionId: z.string().uuid(),
  workDate: z.string(),
  exceptionType: ExceptionTypeSchema,
  severity: ExceptionSeveritySchema,
  status: ExceptionStatusSchema,
  detail: z.record(z.string(), z.unknown()),
  detectedAt: z.string(),
  recordVersion: z.number().int().positive(),
});
export type AttendanceExceptionRow = z.infer<typeof AttendanceExceptionRowSchema>;

export function parseAttendanceExceptionRow(row: Record<string, unknown>): AttendanceExceptionRow {
  return AttendanceExceptionRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id,
    employeeNumber: row.employee_number,
    sessionId: row.session_id,
    workDate: row.work_date,
    exceptionType: row.exception_type,
    severity: row.severity,
    status: row.status,
    detail: row.detail ?? {},
    detectedAt: row.detected_at,
    recordVersion: row.record_version,
  });
}

export const CorrectionRequestRowSchema = z.object({
  id: z.string().uuid(),
  employeeId: z.string().uuid().optional(),
  employeeNumber: z.string().optional(),
  sessionId: z.string().uuid(),
  workDate: z.string(),
  requestType: CorrectionRequestTypeSchema,
  status: CorrectionStatusSchema,
  createdAt: z.string(),
  recordVersion: z.number().int().positive(),
  hasEvidence: z.boolean().optional(),
});
export type CorrectionRequestRow = z.infer<typeof CorrectionRequestRowSchema>;

export function parseCorrectionRequestRow(row: Record<string, unknown>): CorrectionRequestRow {
  return CorrectionRequestRowSchema.parse({
    id: row.id,
    employeeId: row.employee_id ?? undefined,
    employeeNumber: row.employee_number ?? undefined,
    sessionId: row.session_id,
    workDate: row.work_date,
    requestType: row.request_type,
    status: row.status,
    createdAt: row.created_at,
    recordVersion: row.record_version,
    hasEvidence: row.has_evidence ?? undefined,
  });
}

export const AttendancePolicyRowSchema = z.object({
  id: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string(),
  status: PolicyStatusSchema,
  publishedVersionId: z.string().uuid().nullable(),
  publishedVersionNumber: z.number().int().nullable(),
  recordVersion: z.number().int().positive(),
});
export type AttendancePolicyRow = z.infer<typeof AttendancePolicyRowSchema>;

export function parseAttendancePolicyRow(row: Record<string, unknown>): AttendancePolicyRow {
  return AttendancePolicyRowSchema.parse({
    id: row.id,
    orgUnitId: row.org_unit_id ?? null,
    name: row.name,
    status: row.status,
    publishedVersionId: row.published_version_id ?? null,
    publishedVersionNumber: row.published_version_number ?? null,
    recordVersion: row.record_version,
  });
}

export const AttendancePolicyVersionSchema = z.object({
  id: z.string().uuid(),
  policyId: z.string().uuid(),
  tenantId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  status: PolicyVersionStatusSchema,
  effectiveFrom: z.string(),
  timezone: z.string(),
  workdayStartTime: z.string(),
  workdayEndTime: z.string(),
  dayBoundaryLocalTime: z.string(),
  graceLateMinutes: z.number().int().nonnegative(),
  graceEarlyMinutes: z.number().int().nonnegative(),
  allowedChannels: z.array(SourceChannelSchema),
  locationEnforcementMode: LocationEnforcementModeSchema,
  geofenceRadiusMeters: z.number().nullable(),
  maxSessionHours: z.number().positive(),
  recordVersion: z.number().int().positive(),
});
export type AttendancePolicyVersion = z.infer<typeof AttendancePolicyVersionSchema>;

export function parseAttendancePolicyVersion(row: Record<string, unknown>): AttendancePolicyVersion {
  return AttendancePolicyVersionSchema.parse({
    id: row.id,
    policyId: row.policy_id,
    tenantId: row.tenant_id,
    versionNumber: row.version_number,
    status: row.status,
    effectiveFrom: row.effective_from,
    timezone: row.timezone,
    workdayStartTime: row.workday_start_time,
    workdayEndTime: row.workday_end_time,
    dayBoundaryLocalTime: row.day_boundary_local_time,
    graceLateMinutes: row.grace_late_minutes,
    graceEarlyMinutes: row.grace_early_minutes,
    allowedChannels: row.allowed_channels ?? [],
    locationEnforcementMode: row.location_enforcement_mode,
    geofenceRadiusMeters: row.geofence_radius_meters ?? null,
    maxSessionHours: Number(row.max_session_hours),
    recordVersion: row.record_version,
  });
}

// --- Mutation inputs ---

export const RecordAttendanceClockEventInputSchema = z.object({
  tenantId: z.string().uuid(),
  eventType: EventTypeSchema,
  sourceChannel: SelfServiceChannelSchema,
  clientReportedAt: z.string().nullable(),
  locationGeojson: GeoJsonPointSchema.nullable(),
  deviceLabel: z.string().nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordAttendanceClockEventInput = z.infer<typeof RecordAttendanceClockEventInputSchema>;

export const RecordManualAttendanceEventInputSchema = z.object({
  tenantId: z.string().uuid(),
  employeeId: z.string().uuid(),
  eventType: EventTypeSchema,
  eventAt: z.string().min(1),
  reason: z.string().min(1),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecordManualAttendanceEventInput = z.infer<typeof RecordManualAttendanceEventInputSchema>;

export const RequestAttendanceCorrectionInputSchema = z.object({
  sessionId: z.string().uuid(),
  requestType: CorrectionRequestTypeSchema,
  proposedClockInAt: z.string().nullable(),
  proposedClockOutAt: z.string().nullable(),
  reason: z.string().min(1),
  evidenceFileId: z.string().uuid().nullable(),
  idempotencyKey: z.string().min(1).nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RequestAttendanceCorrectionInput = z.infer<typeof RequestAttendanceCorrectionInputSchema>;

export const DecideAttendanceCorrectionInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: CorrectionDecisionSchema,
  decidedReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideAttendanceCorrectionInput = z.infer<typeof DecideAttendanceCorrectionInputSchema>;

export const CancelAttendanceCorrectionInputSchema = z.object({
  requestId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CancelAttendanceCorrectionInput = z.infer<typeof CancelAttendanceCorrectionInputSchema>;

export const AcknowledgeAttendanceExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AcknowledgeAttendanceExceptionInput = z.infer<typeof AcknowledgeAttendanceExceptionInputSchema>;

export const WaiveAttendanceExceptionInputSchema = z.object({
  exceptionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  waiveReason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type WaiveAttendanceExceptionInput = z.infer<typeof WaiveAttendanceExceptionInputSchema>;

export const ApproveAttendanceForPayrollInputInputSchema = z.object({
  tenantId: z.string().uuid(),
  fromDate: z.string().min(1),
  toDate: z.string().min(1),
  employeeId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type ApproveAttendanceForPayrollInputInput = z.infer<typeof ApproveAttendanceForPayrollInputInputSchema>;

export const CreateAttendancePolicyInputSchema = z.object({
  tenantId: z.string().uuid(),
  orgUnitId: z.string().uuid().nullable(),
  name: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateAttendancePolicyInput = z.infer<typeof CreateAttendancePolicyInputSchema>;

export const CreateAttendancePolicyVersionInputSchema = z.object({
  policyId: z.string().uuid(),
  timezone: z.string().min(1),
  workdayStartTime: z.string().min(1),
  workdayEndTime: z.string().min(1),
  dayBoundaryLocalTime: z.string().min(1),
  graceLateMinutes: z.number().int().min(0).max(240),
  graceEarlyMinutes: z.number().int().min(0).max(240),
  allowedChannels: z.array(SourceChannelSchema).min(1),
  locationEnforcementMode: LocationEnforcementModeSchema,
  geofenceCenterGeojson: GeoJsonPointSchema.nullable(),
  geofenceRadiusMeters: z.number().positive().nullable(),
  maxSessionHours: z.number().positive().max(48),
  effectiveFrom: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateAttendancePolicyVersionInput = z.infer<typeof CreateAttendancePolicyVersionInputSchema>;

export const RecalculateAttendanceExceptionsInputSchema = z.object({
  tenantId: z.string().uuid(),
  fromDate: z.string().min(1),
  toDate: z.string().min(1),
  orgUnitId: z.string().uuid().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RecalculateAttendanceExceptionsInput = z.infer<typeof RecalculateAttendanceExceptionsInputSchema>;

export const PublishAttendancePolicyVersionInputSchema = z.object({
  versionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type PublishAttendancePolicyVersionInput = z.infer<typeof PublishAttendancePolicyVersionInputSchema>;
