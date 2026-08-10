/**
 * Attendance mutation primitives (HRT-278, CG-S12-HRT-006). Thin, typed
 * wrappers around every write RPC in
 * supabase/migrations/20260730900000_create_hris_attendance.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  RecordAttendanceClockEventInputSchema,
  RecordManualAttendanceEventInputSchema,
  RequestAttendanceCorrectionInputSchema,
  DecideAttendanceCorrectionInputSchema,
  CancelAttendanceCorrectionInputSchema,
  AcknowledgeAttendanceExceptionInputSchema,
  WaiveAttendanceExceptionInputSchema,
  ApproveAttendanceForPayrollInputInputSchema,
  CreateAttendancePolicyInputSchema,
  CreateAttendancePolicyVersionInputSchema,
  PublishAttendancePolicyVersionInputSchema,
  RecalculateAttendanceExceptionsInputSchema,
  type RecordAttendanceClockEventInput,
  type RecordManualAttendanceEventInput,
  type RequestAttendanceCorrectionInput,
  type DecideAttendanceCorrectionInput,
  type CancelAttendanceCorrectionInput,
  type AcknowledgeAttendanceExceptionInput,
  type WaiveAttendanceExceptionInput,
  type ApproveAttendanceForPayrollInputInput,
  type CreateAttendancePolicyInput,
  type CreateAttendancePolicyVersionInput,
  type PublishAttendancePolicyVersionInput,
  type RecalculateAttendanceExceptionsInput,
} from "../contracts/attendance/attendance.ts";

export type AttendanceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const ATTENDANCE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "employee_not_found",
  "employee_not_active",
  "no_eligible_policy",
  "channel_not_permitted",
  "location_required",
  "outside_geofence",
  "idempotency_key_conflict",
  "duplicate_open_session",
  "duplicate_workday_session",
  "no_open_session",
  "impossible_ordering",
  "invalid_event_type",
  "invalid_source_channel",
  "reason_required",
  "event_at_required",
  "session_not_found",
  "evidence_file_not_found",
  "evidence_file_infected",
  "evidence_file_not_scanned",
  "correction_request_not_found",
  "self_approval_not_permitted",
  "invalid_decision",
  "invalid_transition",
  "exception_not_found",
  "stale_version",
  "invalid_date_range",
  "policy_not_found",
  "policy_version_not_found",
  "invalid_name",
  "org_unit_not_found",
  "invalid_timezone",
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
] as const;

export type KnownAttendanceMutationErrorCode = (typeof ATTENDANCE_KNOWN_MUTATION_ERROR_CODES)[number];
export type AttendanceMutationErrorCode = KnownAttendanceMutationErrorCode | "mutation_failed";

export class AttendanceMutationError extends Error {
  readonly code: AttendanceMutationErrorCode;

  constructor(code: AttendanceMutationErrorCode, message: string) {
    super(message);
    this.name = "AttendanceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): AttendanceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (ATTENDANCE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownAttendanceMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

export async function recordAttendanceClockEvent(client: AttendanceMutationRpcClient, input: RecordAttendanceClockEventInput): Promise<Record<string, unknown>> {
  const parsed = RecordAttendanceClockEventInputSchema.parse(input);
  const { data, error } = await client.rpc("record_attendance_clock_event", {
    p_tenant_id: parsed.tenantId,
    p_event_type: parsed.eventType,
    p_source_channel: parsed.sourceChannel,
    p_client_reported_at: parsed.clientReportedAt,
    p_location_geojson: parsed.locationGeojson,
    p_device_label: parsed.deviceLabel,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "record_attendance_clock_event returned no row");
  return row;
}

export async function recordManualAttendanceEvent(client: AttendanceMutationRpcClient, input: RecordManualAttendanceEventInput): Promise<Record<string, unknown>> {
  const parsed = RecordManualAttendanceEventInputSchema.parse(input);
  const { data, error } = await client.rpc("record_manual_attendance_event", {
    p_tenant_id: parsed.tenantId,
    p_employee_id: parsed.employeeId,
    p_event_type: parsed.eventType,
    p_event_at: parsed.eventAt,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "record_manual_attendance_event returned no row");
  return row;
}

export async function requestAttendanceCorrection(client: AttendanceMutationRpcClient, input: RequestAttendanceCorrectionInput): Promise<Record<string, unknown>> {
  const parsed = RequestAttendanceCorrectionInputSchema.parse(input);
  const { data, error } = await client.rpc("request_attendance_correction", {
    p_session_id: parsed.sessionId,
    p_request_type: parsed.requestType,
    p_proposed_clock_in_at: parsed.proposedClockInAt,
    p_proposed_clock_out_at: parsed.proposedClockOutAt,
    p_reason: parsed.reason,
    p_evidence_file_id: parsed.evidenceFileId,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "request_attendance_correction returned no row");
  return row;
}

export async function decideAttendanceCorrection(client: AttendanceMutationRpcClient, input: DecideAttendanceCorrectionInput): Promise<Record<string, unknown>> {
  const parsed = DecideAttendanceCorrectionInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_attendance_correction", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decided_reason: parsed.decidedReason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "decide_attendance_correction returned no row");
  return row;
}

export async function cancelAttendanceCorrection(client: AttendanceMutationRpcClient, input: CancelAttendanceCorrectionInput): Promise<Record<string, unknown>> {
  const parsed = CancelAttendanceCorrectionInputSchema.parse(input);
  const { data, error } = await client.rpc("cancel_attendance_correction", {
    p_request_id: parsed.requestId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "cancel_attendance_correction returned no row");
  return row;
}

export async function acknowledgeAttendanceException(client: AttendanceMutationRpcClient, input: AcknowledgeAttendanceExceptionInput): Promise<Record<string, unknown>> {
  const parsed = AcknowledgeAttendanceExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("acknowledge_attendance_exception", {
    p_exception_id: parsed.exceptionId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "acknowledge_attendance_exception returned no row");
  return row;
}

export async function waiveAttendanceException(client: AttendanceMutationRpcClient, input: WaiveAttendanceExceptionInput): Promise<Record<string, unknown>> {
  const parsed = WaiveAttendanceExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("waive_attendance_exception", {
    p_exception_id: parsed.exceptionId,
    p_expected_version: parsed.expectedVersion,
    p_waive_reason: parsed.waiveReason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "waive_attendance_exception returned no row");
  return row;
}

export async function approveAttendanceForPayrollInput(client: AttendanceMutationRpcClient, input: ApproveAttendanceForPayrollInputInput): Promise<Record<string, unknown>[]> {
  const parsed = ApproveAttendanceForPayrollInputInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_attendance_for_payroll_input", {
    p_tenant_id: parsed.tenantId,
    p_from_date: parsed.fromDate,
    p_to_date: parsed.toDate,
    p_employee_id: parsed.employeeId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function recalculateAttendanceExceptions(client: AttendanceMutationRpcClient, input: RecalculateAttendanceExceptionsInput): Promise<number> {
  const parsed = RecalculateAttendanceExceptionsInputSchema.parse(input);
  const { data, error } = await client.rpc("recalculate_attendance_exceptions_for_range", {
    p_tenant_id: parsed.tenantId,
    p_from_date: parsed.fromDate,
    p_to_date: parsed.toDate,
    p_org_unit_id: parsed.orgUnitId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  return Number(data ?? 0);
}

export async function createAttendancePolicy(client: AttendanceMutationRpcClient, input: CreateAttendancePolicyInput): Promise<Record<string, unknown>> {
  const parsed = CreateAttendancePolicyInputSchema.parse(input);
  const { data, error } = await client.rpc("create_attendance_policy", {
    p_tenant_id: parsed.tenantId,
    p_org_unit_id: parsed.orgUnitId,
    p_name: parsed.name,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "create_attendance_policy returned no row");
  return row;
}

export async function createAttendancePolicyVersion(client: AttendanceMutationRpcClient, input: CreateAttendancePolicyVersionInput): Promise<Record<string, unknown>> {
  const parsed = CreateAttendancePolicyVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("create_attendance_policy_version", {
    p_policy_id: parsed.policyId,
    p_timezone: parsed.timezone,
    p_workday_start_time: parsed.workdayStartTime,
    p_workday_end_time: parsed.workdayEndTime,
    p_day_boundary_local_time: parsed.dayBoundaryLocalTime,
    p_grace_late_minutes: parsed.graceLateMinutes,
    p_grace_early_minutes: parsed.graceEarlyMinutes,
    p_allowed_channels: parsed.allowedChannels,
    p_location_enforcement_mode: parsed.locationEnforcementMode,
    p_geofence_center_geojson: parsed.geofenceCenterGeojson,
    p_geofence_radius_meters: parsed.geofenceRadiusMeters,
    p_max_session_hours: parsed.maxSessionHours,
    p_effective_from: parsed.effectiveFrom,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "create_attendance_policy_version returned no row");
  return row;
}

export async function publishAttendancePolicyVersion(client: AttendanceMutationRpcClient, input: PublishAttendancePolicyVersionInput): Promise<Record<string, unknown>> {
  const parsed = PublishAttendancePolicyVersionInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_attendance_policy_version", {
    p_version_id: parsed.versionId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new AttendanceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new AttendanceMutationError("mutation_failed", "publish_attendance_policy_version returned no row");
  return row;
}
