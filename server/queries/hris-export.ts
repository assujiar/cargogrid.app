/**
 * HRIS bulk-export read queries (ISS-2026-075). Thin, typed wrappers around the four
 * `HRS:Export`-gated export RPCs that had none: `app.export_attendance_sessions`
 * (HRT-278), `app.export_schedule_assignments` (HRT-279), `app.export_leave_requests`
 * (HRT-280) and `app.export_timesheet_entries` (HRT-281).
 *
 * WHY ALL FOUR, WHEN THE ENTRY WAS FILED ABOUT ONE
 *
 *   `ISS-2026-075` was raised against the timesheet export as a HIGH, capability-specific
 *   gap, and its own re-verification corrected that: the other three sibling exports had
 *   identically zero wrapper, so this was a repository-wide pattern rather than something
 *   HRT-281 shipped worse than precedent. The disposition that followed from the
 *   correction is the one honoured here -- wire all four at once, "so the fix lands once,
 *   consistently, rather than piecemeal per capability."
 *
 * THE ONE THING THESE WRAPPERS DO THAT THE RPCs DO NOT
 *
 *   Every one of the four RPCs answers a caller who lacks `HRS:Export` with `return;` --
 *   an empty result set, not an error. At the SQL layer that is a defensible
 *   deny-by-default. Through a UI it is actively misleading: the button appears to work,
 *   a file downloads, and it is empty, so the reader concludes there was nothing to
 *   export rather than that they were not allowed to.
 *
 *   `assertHrisExportAuthority` closes that gap without touching the applied migrations
 *   or weakening anything: it evaluates `HRS:Export` explicitly, first, and throws
 *   `insufficient_authority` so the caller can say which of the two actually happened.
 *   The RPC's own gate remains the real boundary and is unchanged -- this check can only
 *   refuse earlier, never permit something the RPC would refuse.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { evaluatePermission, RbacEvaluationError, type RbacRpcClient } from "./rbac.ts";
import {
  HRIS_EXPORT_MAX_RANGE_DAYS,
  parseAttendanceSessionExportRow,
  parseLeaveRequestExportRow,
  parseScheduleAssignmentExportRow,
  parseTimesheetEntryExportRow,
  type AttendanceSessionExportRow,
  type LeaveRequestExportRow,
  type ScheduleAssignmentExportRow,
  type TimesheetEntryExportRow,
} from "../contracts/hris-export/hris-export.ts";

export type HrisExportQueryClient = Pick<SupabaseClient, "rpc">;

const KNOWN_QUERY_ERROR_CODES = ["insufficient_authority", "invalid_date_range", "actor_identity_mismatch"] as const;
type KnownQueryErrorCode = (typeof KNOWN_QUERY_ERROR_CODES)[number];
export type HrisExportQueryErrorCode = KnownQueryErrorCode | "query_failed";

export class HrisExportQueryError extends Error {
  readonly code: HrisExportQueryErrorCode;

  constructor(message: string) {
    super(message);
    this.name = "HrisExportQueryError";
    const prefix = message.split(":")[0]?.trim();
    this.code = (KNOWN_QUERY_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownQueryErrorCode) : "query_failed";
  }
}

export interface HrisExportRange {
  readonly fromDate: string;
  readonly toDate: string;
}

/**
 * The same range rule the RPCs enforce, checked here so a bad range is a clear message
 * rather than a round trip that raises. Never a replacement for the server check -- a
 * caller bypassing this wrapper still hits `invalid_date_range` at the RPC.
 */
function assertRange(range: HrisExportRange): void {
  const from = Date.parse(range.fromDate);
  const to = Date.parse(range.toDate);
  if (Number.isNaN(from) || Number.isNaN(to)) {
    throw new HrisExportQueryError("invalid_date_range: both a from-date and a to-date are required");
  }
  if (to < from) {
    throw new HrisExportQueryError("invalid_date_range: the to-date cannot be earlier than the from-date");
  }
  const days = Math.round((to - from) / 86_400_000);
  if (days > HRIS_EXPORT_MAX_RANGE_DAYS) {
    throw new HrisExportQueryError(`invalid_date_range: export date range must be at most ${HRIS_EXPORT_MAX_RANGE_DAYS} days`);
  }
}

/**
 * Throws `insufficient_authority` when the actor lacks `HRS:Export`, so an empty export
 * can only ever mean "no rows in this range". See the module header for why this exists
 * rather than being left to the RPC's own silent empty result.
 */
export async function assertHrisExportAuthority(client: HrisExportQueryClient, tenantId: string, actorAuthUserId: string): Promise<void> {
  let allowed: boolean;
  let reason: string;
  try {
    const decision = await evaluatePermission(client as unknown as RbacRpcClient, {
      authUserId: actorAuthUserId,
      tenantId,
      resourceModuleCode: "HRS",
      action: "Export",
    });
    allowed = decision.allowed;
    reason = decision.reason;
  } catch (error) {
    if (error instanceof RbacEvaluationError) {
      throw new HrisExportQueryError(`query_failed: ${error.message}`);
    }
    throw error;
  }
  if (!allowed) {
    throw new HrisExportQueryError(`insufficient_authority: HRS:Export is required to export HR data (${reason})`);
  }
}

async function runExport(
  client: HrisExportQueryClient,
  fn: string,
  tenantId: string,
  actorAuthUserId: string,
  range: HrisExportRange,
): Promise<Record<string, unknown>[]> {
  assertRange(range);
  await assertHrisExportAuthority(client, tenantId, actorAuthUserId);
  const { data, error } = await client.rpc(fn, {
    p_tenant_id: tenantId,
    p_actor_auth_user_id: actorAuthUserId,
    p_from_date: range.fromDate,
    p_to_date: range.toDate,
  });
  if (error) {
    throw new HrisExportQueryError(error.message);
  }
  return (data as Record<string, unknown>[] | null) ?? [];
}

/** Attendance sessions in the range (HRT-278). `HRS:Export`. */
export async function exportAttendanceSessions(
  client: HrisExportQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  range: HrisExportRange,
): Promise<AttendanceSessionExportRow[]> {
  return (await runExport(client, "export_attendance_sessions", tenantId, actorAuthUserId, range)).map(parseAttendanceSessionExportRow);
}

/** Shift/roster assignments in the range (HRT-279). `HRS:Export`. */
export async function exportScheduleAssignments(
  client: HrisExportQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  range: HrisExportRange,
): Promise<ScheduleAssignmentExportRow[]> {
  return (await runExport(client, "export_schedule_assignments", tenantId, actorAuthUserId, range)).map(parseScheduleAssignmentExportRow);
}

/** Leave/permit/business-trip requests overlapping the range (HRT-280). `HRS:Export`. The RPC deliberately omits reason/destination/evidence columns regardless of the caller's own personal-data standing. */
export async function exportLeaveRequests(
  client: HrisExportQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  range: HrisExportRange,
): Promise<LeaveRequestExportRow[]> {
  return (await runExport(client, "export_leave_requests", tenantId, actorAuthUserId, range)).map(parseLeaveRequestExportRow);
}

/** Timesheet entries in the range (HRT-281) -- the export `ISS-2026-075` was originally filed about. `HRS:Export`. */
export async function exportTimesheetEntries(
  client: HrisExportQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  range: HrisExportRange,
): Promise<TimesheetEntryExportRow[]> {
  return (await runExport(client, "export_timesheet_entries", tenantId, actorAuthUserId, range)).map(parseTimesheetEntryExportRow);
}
