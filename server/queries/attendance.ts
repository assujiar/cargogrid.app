/**
 * Attendance read queries (HRT-278, CG-S12-HRT-006). Thin, typed wrappers
 * around every read RPC in
 * supabase/migrations/20260730900000_create_hris_attendance.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  parseMyAttendanceStatus,
  parseSessionListRow,
  parseSessionDetail,
  parseAttendanceExceptionRow,
  parseCorrectionRequestRow,
  parseAttendancePolicyRow,
  parseAttendancePolicyVersion,
  type MyAttendanceStatus,
  type SessionListRow,
  type SessionDetail,
  type AttendanceExceptionRow,
  type CorrectionRequestRow,
  type AttendancePolicyRow,
  type AttendancePolicyVersion,
} from "../contracts/attendance/attendance.ts";

export type AttendanceQueryClient = Pick<SupabaseClient, "rpc">;

export class AttendanceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AttendanceQueryError";
  }
}

function rows(data: unknown): Record<string, unknown>[] {
  return (data as Record<string, unknown>[] | null) ?? [];
}

export async function getMyAttendanceStatus(client: AttendanceQueryClient, tenantId: string, actorAuthUserId: string): Promise<MyAttendanceStatus[]> {
  const { data, error } = await client.rpc("get_my_attendance_status", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new AttendanceQueryError(error.message);
  return rows(data).map(parseMyAttendanceStatus);
}

export async function listAttendanceSessions(
  client: AttendanceQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { fromDate?: string | null; toDate?: string | null; employeeId?: string | null; status?: string | null; limit?: number; afterId?: string | null },
): Promise<SessionListRow[]> {
  const { data, error } = await client.rpc("list_attendance_sessions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_from_date: options?.fromDate ?? null,
    p_to_date: options?.toDate ?? null,
    p_employee_id: options?.employeeId ?? null,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new AttendanceQueryError(error.message);
  return rows(data).map(parseSessionListRow);
}

export async function getAttendanceSessionDetail(client: AttendanceQueryClient, sessionId: string, actorAuthUserId: string): Promise<SessionDetail | null> {
  const { data, error } = await client.rpc("get_attendance_session_detail", { p_session_id: sessionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new AttendanceQueryError(error.message);
  const row = rows(data)[0];
  return row ? parseSessionDetail(row) : null;
}

export async function listAttendanceExceptions(
  client: AttendanceQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { status?: string | null; limit?: number; afterId?: string | null },
): Promise<AttendanceExceptionRow[]> {
  const { data, error } = await client.rpc("list_attendance_exceptions", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new AttendanceQueryError(error.message);
  return rows(data).map(parseAttendanceExceptionRow);
}

export async function listMyAttendanceCorrectionRequests(client: AttendanceQueryClient, tenantId: string, actorAuthUserId: string): Promise<CorrectionRequestRow[]> {
  const { data, error } = await client.rpc("list_my_attendance_correction_requests", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new AttendanceQueryError(error.message);
  return rows(data).map(parseCorrectionRequestRow);
}

export async function listAttendanceCorrectionRequests(
  client: AttendanceQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: { status?: string | null; limit?: number; afterId?: string | null },
): Promise<CorrectionRequestRow[]> {
  const { data, error } = await client.rpc("list_attendance_correction_requests", {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_status: options?.status ?? null,
    p_limit: options?.limit ?? 50,
    p_after_id: options?.afterId ?? null,
  });
  if (error) throw new AttendanceQueryError(error.message);
  return rows(data).map(parseCorrectionRequestRow);
}

export async function listAttendancePolicies(client: AttendanceQueryClient, tenantId: string, actorAuthUserId: string): Promise<AttendancePolicyRow[]> {
  const { data, error } = await client.rpc("list_attendance_policies", { p_tenant_id: tenantId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new AttendanceQueryError(error.message);
  return rows(data).map(parseAttendancePolicyRow);
}

export async function getAttendancePolicyVersion(client: AttendanceQueryClient, versionId: string, actorAuthUserId: string): Promise<AttendancePolicyVersion | null> {
  const { data, error } = await client.rpc("get_attendance_policy_version", { p_version_id: versionId, p_actor_auth_user_id: actorAuthUserId });
  if (error) throw new AttendanceQueryError(error.message);
  if (!data) return null;
  const row = Array.isArray(data) ? data[0] : data;
  return row ? parseAttendancePolicyVersion(row as Record<string, unknown>) : null;
}
