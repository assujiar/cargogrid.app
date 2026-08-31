/**
 * Employee and Manager Self-Service (ESS/MSS) composition reads (HRT-285,
 * CG-S12-HRT-013). Every function below composes exclusively from the
 * ALREADY-VERIFIED/COMPLETED canonical HR capabilities' own read RPCs
 * (HRT-274 employee master, HRT-278 attendance, HRT-279 shift/roster,
 * HRT-280 leave, HRT-281 overtime/timesheet, HRT-282 payroll, HRT-283 KPI/
 * performance, HRT-284 training/talent) -- no new RPC, no new table read, no
 * new authority logic. Own/team scope is never re-derived here: every "team"
 * list below is the OWNING capability's own self/direct-manager/`HRS:View`
 * (or `HRS:View personal data`) scoped RPC, called with `employeeId: null`
 * so its OWN embedded scope resolution applies, then defensively re-filtered
 * (below) to the caller's OWN `app.list_my_team_employees` roster -- the
 * SAME effective-team resolution HRT-274 already established (never a
 * second manager-hierarchy mechanism, per Prompt 285 section 24/26).
 *
 * Deliberately excluded from the manager team workspace (not merely
 * unimplemented -- disclosed, see the build log): attendance-correction
 * decisions and schedule-swap decisions. `app.list_attendance_correction_
 * requests`/`app.list_schedule_swap_requests` (HRT-278/279) gate on plain
 * `HRS:View` ONLY -- there is no self/direct-manager branch in either
 * function's own predicate (verified directly against the migration SQL,
 * not assumed from precedent) -- so these are genuinely HR-admin-only
 * capabilities in this repository today, not an MSS-eligible manager
 * action; composing them here would either always render empty for a bare
 * manager (dead UI) or require this checkpoint to invent a NEW manager-scope
 * predicate those capabilities' own owners never built -- forbidden by
 * section 13 ("never re-implement... any of their logic"). Also excluded:
 * every talent-review/pool/succession read (`HRS:Override`-only per HRT-284
 * decision 6, never self, never direct manager -- "manager status alone
 * must never grant... talent... data", section 16) and every payroll read
 * beyond the caller's own ESS payslip/reimbursement/loan (section 15 scopes
 * payroll to ESS "own payslip/benefit" only; the MSS team workspace never
 * touches `app.payroll_*` at all).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import { getMyEmployeeProfile, listMyTeamEmployees, EmployeeQueryError } from "./employee.ts";
import { getMyAttendanceStatus, AttendanceQueryError } from "./attendance.ts";
import { getMySchedule, listScheduleAssignments, ShiftRosterQueryError } from "./shift-roster.ts";
import { listLeaveApprovalInboxForActor, getLeaveRequestDetail, listLeaveRequests, LeaveQueryError } from "./leave.ts";
import {
  listMyOvertimeRequests,
  listOvertimeRequests,
  listMyTimesheetEntries,
  listTimesheetEntries,
  OvertimeTimesheetQueryError,
} from "./overtime-timesheet.ts";
import { listMyPayslips, listMyPayrollReimbursementRequests, listMyPayrollLoans, PayrollQueryError } from "./payroll.ts";
import {
  listMyPerformanceGoalAssignments,
  listMyPerformanceOutcomes,
  listPerformanceCycles,
  listPerformanceGoalAssignments,
  listPerformanceOutcomes,
  PerformanceQueryError,
} from "./kpi-performance.ts";
import {
  listMyTrainingEnrollments,
  listMyTrainingCertificates,
  listMyTrainingDevelopmentPlans,
  listMyTalentReviewAssignments,
  listTrainingEnrollments,
  listTrainingCertificates,
  TrainingTalentQueryError,
} from "./training-talent.ts";
import type { EssHomeSummary, ManagerApprovalQueueItem, MssTeamWorkspace } from "../contracts/self-service/self-service.ts";
import type { PerformanceCycleRow } from "../contracts/kpi-performance/kpi-performance.ts";

export type SelfServiceQueryClient = Pick<SupabaseClient, "rpc" | "from">;

export class SelfServiceQueryError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "SelfServiceQueryError";
  }
}

/** Every owning capability's own query error class is normalized to one type here -- the composition layer's own consumers (ESS/MSS pages) need to catch exactly one error type, never six. The original message (which already carries the owning RPC's own classifiable error code prefix) is preserved unchanged. */
function toSelfServiceError(error: unknown): SelfServiceQueryError {
  if (
    error instanceof EmployeeQueryError ||
    error instanceof AttendanceQueryError ||
    error instanceof ShiftRosterQueryError ||
    error instanceof LeaveQueryError ||
    error instanceof OvertimeTimesheetQueryError ||
    error instanceof PayrollQueryError ||
    error instanceof PerformanceQueryError ||
    error instanceof TrainingTalentQueryError
  ) {
    return new SelfServiceQueryError(error.message);
  }
  return new SelfServiceQueryError(error instanceof Error ? error.message : String(error));
}

/** Exported (not merely a private const) so the UI can render an honest "showing up to N" disclosure instead of a hardcoded duplicate literal drifting out of sync -- batch 283-285 Tier C fix, spec-compliance lens finding 3. */
export const TEAM_QUEUE_BOUND = 20;
const TEAM_LIST_BOUND = 50;

/**
 * ISS-2026-084. The page sizes a caller may ask for, and the ceiling they may not
 * exceed -- both live here rather than in the page, so a URL cannot ask for an
 * unbounded queue and the disclosure banner cannot drift from what was fetched.
 *
 * The ceiling is not the same kind of number for both lists, and the difference is
 * worth stating because it is what kept this entry open twice:
 *
 *   - The team roster is genuinely server-paged. `app.list_my_team_employees` orders by
 *     employee number, takes an `after` cursor and caps itself at 200, so paging it is
 *     real cursor traversal, not a bigger fetch.
 *   - Three of the four approval queues were ALREADY fetched in full (up to 200) and
 *     then sliced to 20 for display -- the bound bought nothing there except hiding
 *     rows the composition had already paid for. Raising it costs no extra round trip.
 *   - The leave queue is the one exception, and the reason the ceiling is not simply
 *     removed: it slices BEFORE resolving each step's own detail, so every additional
 *     item is a real extra RPC call. `TEAM_QUEUE_MAX` is what stops a hand-edited URL
 *     from turning one page load into hundreds of round trips.
 */
export const TEAM_QUEUE_SIZES = [20, 50, 100] as const;
export const TEAM_QUEUE_MAX = 100;
export const TEAM_PAGE_SIZE = TEAM_LIST_BOUND;

export interface MssTeamWorkspaceOptions {
  /** Employee number to page past, from a previous page's own `nextTeamCursor`. Null for the first page. */
  readonly teamAfterEmployeeNumber?: string | null;
  /** Items shown per approval-queue category. Clamped to TEAM_QUEUE_SIZES' own range; anything else falls back to the default. */
  readonly queueLimit?: number | null;
}

function clampQueueLimit(requested: number | null | undefined): number {
  if (requested === null || requested === undefined || !Number.isFinite(requested)) return TEAM_QUEUE_BOUND;
  return Math.min(Math.max(Math.trunc(requested), TEAM_QUEUE_BOUND), TEAM_QUEUE_MAX);
}

// --- ESS home ---

export async function getEssHomeSummary(client: SelfServiceQueryClient, tenantId: string, actorAuthUserId: string): Promise<EssHomeSummary> {
  try {
    const [
      profile,
      attendanceStatuses,
      mySchedule,
      pendingLeaveInbox,
      myOvertimeRequests,
      myTimesheetEntries,
      myPayslips,
      myReimbursements,
      myLoans,
      myGoals,
      myOutcomes,
      myEnrollments,
      myDevelopmentPlans,
      myTalentReviewAssignments,
    ] = await Promise.all([
      getMyEmployeeProfile(client, tenantId, actorAuthUserId),
      getMyAttendanceStatus(client, tenantId, actorAuthUserId),
      getMySchedule(client, tenantId, actorAuthUserId, { fromDate: todayIso(), toDate: addDaysIso(14) }),
      listLeaveApprovalInboxForActor(client, tenantId, actorAuthUserId), // used below only to size an *approver* inbox, not this employee's own pending requests -- kept out of ESS counts (see decision note in the mutations layer)
      listMyOvertimeRequests(client, tenantId, actorAuthUserId, { limit: 200 }),
      listMyTimesheetEntries(client, tenantId, actorAuthUserId, { limit: 200 }),
      listMyPayslips(client, tenantId, actorAuthUserId),
      listMyPayrollReimbursementRequests(client, tenantId, actorAuthUserId),
      listMyPayrollLoans(client, tenantId, actorAuthUserId),
      listMyPerformanceGoalAssignments(client, tenantId, actorAuthUserId),
      listMyPerformanceOutcomes(client, tenantId, actorAuthUserId),
      listMyTrainingEnrollments(client, tenantId, actorAuthUserId),
      listMyTrainingDevelopmentPlans(client, tenantId, actorAuthUserId),
      listMyTalentReviewAssignments(client, tenantId, actorAuthUserId),
    ]);
    void pendingLeaveInbox;

    const today = attendanceStatuses[0] ?? null;
    const latestPayslipRow = myPayslips[0] ?? null;

    // `list_leave_requests` (HRT-280) accepts an `employeeId` filter -- never
    // a client-supplied value, always the caller's OWN server-resolved
    // `masterRecordId` from the profile already fetched above -- and its own
    // RLS/authority predicate always permits `r.employee_id =
    // v_self.master_record_id` for the calling identity regardless of role,
    // so this can never disclose anything beyond what the caller could
    // already see. Batch 283-285 Tier C fix (spec-compliance lens finding
    // 4): replaces the previous hardcoded `0` placeholder, which shipped a
    // fake value on a public contract alongside otherwise-real sibling
    // counts.
    const myPendingLeaveRequests = profile
      ? await listLeaveRequests(client, tenantId, actorAuthUserId, { employeeId: profile.masterRecordId, status: "pending_approval", limit: 200 })
      : [];

    return {
      hasEmployeeProfile: profile !== null,
      attendanceToday: {
        status: today?.status ?? null,
        clockedIn: today !== null && today.effectiveClockInAt !== null && today.effectiveClockOutAt === null,
        openExceptionCount: today?.openExceptionCount ?? 0,
      },
      upcomingScheduleCount: mySchedule.length,
      pendingLeaveRequestCount: myPendingLeaveRequests.length,
      pendingOvertimeRequestCount: myOvertimeRequests.filter((r) => r.status === "pending_approval").length,
      pendingTimesheetEntryCount: myTimesheetEntries.filter((r) => r.status === "pending_approval").length,
      latestPayslip: latestPayslipRow ? { payslipId: latestPayslipRow.id, currency: latestPayslipRow.currency, netPay: latestPayslipRow.netPay } : null,
      pendingReimbursementCount: myReimbursements.filter((r) => r.status === "pending_approval").length,
      activeLoanCount: myLoans.filter((l) => l.status === "active").length,
      myGoalCount: myGoals.length,
      myPendingOutcomeAcknowledgementCount: myOutcomes.filter((o) => o.status === "published").length,
      myEnrolledTrainingCount: myEnrollments.filter((e) => e.status === "enrolled" || e.status === "waitlisted").length,
      myPendingTrainingApprovalCount: myEnrollments.filter((e) => e.status === "pending_approval").length,
      myActiveDevelopmentPlanCount: myDevelopmentPlans.filter((p) => p.status === "active").length,
      myAssignedTalentReviewCount: myTalentReviewAssignments.filter((a) => a.status === "active").length,
    };
  } catch (error) {
    throw toSelfServiceError(error);
  }
}

// --- MSS team workspace ---

function todayIso(): string {
  return new Date().toISOString().slice(0, 10);
}
function addDaysIso(days: number): string {
  const d = new Date();
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

/** Picks the cycle the manager summary should show: prefer the most-recently-started cycle that is not draft/closed/cancelled (an in-flight cycle); fall back to the most recently ended cycle so a just-closed cycle's own outcomes remain visible for a short window. Never invents a "current" concept the owning capability itself does not already expose via `status`/`period_end` -- purely a client-side pick over rows the RPC already returned in full. */
function pickCurrentCycle(cycles: readonly PerformanceCycleRow[]): PerformanceCycleRow | null {
  const inFlight = cycles.filter((c) => c.status !== "draft" && c.status !== "closed" && c.status !== "cancelled");
  const pool = inFlight.length > 0 ? inFlight : cycles.filter((c) => c.status === "closed");
  if (pool.length === 0) return null;
  return [...pool].sort((a, b) => (a.periodEnd < b.periodEnd ? 1 : -1))[0] ?? null;
}

export async function getMssTeamWorkspace(
  client: SelfServiceQueryClient,
  tenantId: string,
  actorAuthUserId: string,
  options?: MssTeamWorkspaceOptions,
): Promise<MssTeamWorkspace> {
  const queueLimit = clampQueueLimit(options?.queueLimit);
  try {
    // Batch 283-285 Tier C fix (spec-compliance lens finding 3): fetch one
    // row past the bound so a genuine "more than TEAM_LIST_BOUND direct
    // reports" case can be surfaced to the caller (`teamTruncated`) instead
    // of silently dropping members 51+ with no signal anywhere in the UI.
    // That fix's own closing sentence -- "this checkpoint still bounds to a single page
    // but no longer hides that a boundary was hit" -- is what ISS-2026-084 was filed
    // against, and is now out of date: the cursor `app.list_my_team_employees` has
    // always accepted is finally used. The over-fetch-by-one is unchanged and still
    // computes `teamTruncated`; what is new is that the boundary now carries a way
    // across it, which keeps section 17's "bounded server composition" contract intact
    // (every page is still bounded) while dropping the part that was never in that
    // contract -- that the reader may only ever see page one.
    const teamPage = await listMyTeamEmployees(client, tenantId, actorAuthUserId, {
      limit: TEAM_LIST_BOUND + 1,
      afterEmployeeNumber: options?.teamAfterEmployeeNumber ?? null,
    });
    const teamTruncated = teamPage.length > TEAM_LIST_BOUND;
    const team = teamTruncated ? teamPage.slice(0, TEAM_LIST_BOUND) : teamPage;
    if (team.length === 0) {
      // A manager paged past their own last direct report lands here. `isManager: false`
      // would be a lie in that case -- they are a manager, they are simply off the end --
      // so the cursor is what distinguishes "not a manager" from "empty page".
      return {
        isManager: (options?.teamAfterEmployeeNumber ?? null) !== null,
        team: [],
        teamTruncated: false,
        nextTeamCursor: null,
        queueLimit,
        approvalQueue: [],
        approvalQueueTruncated: false,
        teamScheduleUpcoming: [],
        currentPerformanceCycle: null,
        teamGoalAssignments: [],
        teamOutcomes: [],
        teamTrainingEnrollments: [],
        teamCertificates: [],
      };
    }
    const teamIds = new Set(team.map((t) => t.masterRecordId));
    const nameById = new Map(team.map((t) => [t.masterRecordId, t.fullName] as const));

    const [
      leaveInboxSteps,
      overtimePending,
      timesheetPending,
      teamSchedule,
      cycles,
      teamEnrollments,
      teamCertificates,
    ] = await Promise.all([
      listLeaveApprovalInboxForActor(client, tenantId, actorAuthUserId),
      listOvertimeRequests(client, tenantId, actorAuthUserId, { status: "pending_approval", limit: 200 }),
      listTimesheetEntries(client, tenantId, actorAuthUserId, { status: "pending_approval", limit: 200 }),
      listScheduleAssignments(client, tenantId, actorAuthUserId, { fromDate: todayIso(), toDate: addDaysIso(14), limit: 200 }),
      listPerformanceCycles(client, tenantId, actorAuthUserId),
      listTrainingEnrollments(client, tenantId, actorAuthUserId, null, null, null),
      listTrainingCertificates(client, tenantId, actorAuthUserId),
    ]);

    const currentCycle = pickCurrentCycle(cycles);
    const [teamGoalAssignments, teamOutcomes] = currentCycle
      ? await Promise.all([
          listPerformanceGoalAssignments(client, tenantId, currentCycle.id, actorAuthUserId),
          listPerformanceOutcomes(client, tenantId, currentCycle.id, actorAuthUserId),
        ])
      : [[], []];

    const leaveQueueItems: ManagerApprovalQueueItem[] = [];
    for (const step of leaveInboxSteps.slice(0, queueLimit)) {
      const detail = await getLeaveRequestDetail(client, step.leaveRequestId, actorAuthUserId);
      if (!detail || detail.status !== "pending_approval") continue;
      if (!teamIds.has(detail.employeeId)) continue; // defense in depth (business rule 26): the workflow inbox can carry a delegated approval outside the direct-report set -- this queue is scoped to the manager's own effective team only, per this checkpoint's own scope.
      leaveQueueItems.push({
        kind: "leave",
        requestStepId: step.stepId,
        leaveRequestId: step.leaveRequestId,
        employeeId: detail.employeeId,
        employeeName: nameById.get(detail.employeeId) ?? null,
        summary: `Leave ${detail.dateFrom} to ${detail.dateTo} (${detail.dayPortion}, ${detail.totalUnits} unit${detail.totalUnits === 1 ? "" : "s"})`,
        recordVersion: detail.recordVersion,
      });
    }

    const overtimeTeamScoped = overtimePending.filter((r) => teamIds.has(r.employeeId));
    const overtimeQueueItems: ManagerApprovalQueueItem[] = overtimeTeamScoped
      .slice(0, queueLimit)
      .map((r) => ({
        kind: "overtime" as const,
        requestId: r.id,
        employeeId: r.employeeId,
        employeeName: nameById.get(r.employeeId) ?? r.employeeFullName ?? null,
        summary: `Overtime ${r.workDate}, ${r.requestedMinutes} min requested`,
        recordVersion: r.recordVersion,
      }));

    const timesheetTeamScoped = timesheetPending.filter((r) => teamIds.has(r.employeeId));
    const timesheetQueueItems: ManagerApprovalQueueItem[] = timesheetTeamScoped
      .slice(0, queueLimit)
      .map((r) => ({
        kind: "timesheet_entry" as const,
        entryId: r.id,
        employeeId: r.employeeId,
        employeeName: nameById.get(r.employeeId) ?? r.employeeFullName ?? null,
        summary: `Timesheet ${r.workDate}, ${r.entryMinutes} min`,
        recordVersion: r.recordVersion,
      }));

    const trainingTeamScoped = teamEnrollments.filter((e) => e.status === "pending_approval" && e.employeeId && teamIds.has(e.employeeId));
    const trainingQueueItems: ManagerApprovalQueueItem[] = trainingTeamScoped
      .slice(0, queueLimit)
      .map((e) => ({
        kind: "training_enrollment" as const,
        enrollmentId: e.id,
        employeeId: e.employeeId as string,
        employeeName: nameById.get(e.employeeId as string) ?? e.employeeFullName ?? null,
        summary: `${e.courseName ?? "Training"} — session ${e.sessionCode ?? ""}`.trim(),
        recordVersion: e.recordVersion,
      }));

    // Batch 283-285 Tier C fix (spec-compliance lens finding 3): the leave
    // queue slices the RAW (not-yet-team-filtered) inbox before resolving
    // each step's own employee, so its own team-scoped count is not known
    // without a per-step detail fetch this composition layer already pays
    // for above -- `leaveInboxSteps.length > TEAM_QUEUE_BOUND` is a
    // deliberately conservative (may over-flag) proxy for "more pending
    // leave approvals may exist than shown", consistent with this queue's
    // own pre-existing fetch order. The other three queues compute the
    // precise team-scoped truncation signal directly.
    const approvalQueueTruncated =
      leaveInboxSteps.length > queueLimit ||
      overtimeTeamScoped.length > queueLimit ||
      timesheetTeamScoped.length > queueLimit ||
      trainingTeamScoped.length > queueLimit;

    return {
      isManager: true,
      team,
      teamTruncated,
      // Only meaningful when a further page exists; the last page must not offer a
      // "next" that would return nothing.
      nextTeamCursor: teamTruncated ? (team[team.length - 1]?.employeeNumber ?? null) : null,
      queueLimit,
      approvalQueue: [...leaveQueueItems, ...overtimeQueueItems, ...timesheetQueueItems, ...trainingQueueItems],
      approvalQueueTruncated,
      teamScheduleUpcoming: teamSchedule.filter((a) => teamIds.has(a.employeeId)),
      currentPerformanceCycle: currentCycle,
      teamGoalAssignments: teamGoalAssignments.filter((g) => teamIds.has(g.employeeId)),
      teamOutcomes: teamOutcomes.filter((o) => teamIds.has(o.employeeId)),
      teamTrainingEnrollments: teamEnrollments.filter((e) => e.employeeId !== undefined && teamIds.has(e.employeeId)),
      teamCertificates: teamCertificates.filter((c) => c.employeeId !== undefined && teamIds.has(c.employeeId)),
    };
  } catch (error) {
    throw toSelfServiceError(error);
  }
}
