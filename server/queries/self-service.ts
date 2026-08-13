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
import { listLeaveApprovalInboxForActor, getLeaveRequestDetail, LeaveQueryError } from "./leave.ts";
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

const TEAM_QUEUE_BOUND = 20;
const TEAM_LIST_BOUND = 50;

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

    return {
      hasEmployeeProfile: profile !== null,
      attendanceToday: {
        status: today?.status ?? null,
        clockedIn: today !== null && today.effectiveClockInAt !== null && today.effectiveClockOutAt === null,
        openExceptionCount: today?.openExceptionCount ?? 0,
      },
      upcomingScheduleCount: mySchedule.length,
      pendingLeaveRequestCount: 0, // no `list_my_leave_requests` RPC exists (leave.ts only exposes the tenant-scoped `listLeaveRequests`, gated by the caller's own scope) -- disclosed in the build log rather than approximated with a client-supplied employee id.
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

export async function getMssTeamWorkspace(client: SelfServiceQueryClient, tenantId: string, actorAuthUserId: string): Promise<MssTeamWorkspace> {
  try {
    const team = await listMyTeamEmployees(client, tenantId, actorAuthUserId, { limit: TEAM_LIST_BOUND });
    if (team.length === 0) {
      return {
        isManager: false,
        team: [],
        approvalQueue: [],
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
    for (const step of leaveInboxSteps.slice(0, TEAM_QUEUE_BOUND)) {
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

    const overtimeQueueItems: ManagerApprovalQueueItem[] = overtimePending
      .filter((r) => teamIds.has(r.employeeId))
      .slice(0, TEAM_QUEUE_BOUND)
      .map((r) => ({
        kind: "overtime" as const,
        requestId: r.id,
        employeeId: r.employeeId,
        employeeName: nameById.get(r.employeeId) ?? r.employeeFullName ?? null,
        summary: `Overtime ${r.workDate}, ${r.requestedMinutes} min requested`,
        recordVersion: r.recordVersion,
      }));

    const timesheetQueueItems: ManagerApprovalQueueItem[] = timesheetPending
      .filter((r) => teamIds.has(r.employeeId))
      .slice(0, TEAM_QUEUE_BOUND)
      .map((r) => ({
        kind: "timesheet_entry" as const,
        entryId: r.id,
        employeeId: r.employeeId,
        employeeName: nameById.get(r.employeeId) ?? r.employeeFullName ?? null,
        summary: `Timesheet ${r.workDate}, ${r.entryMinutes} min`,
        recordVersion: r.recordVersion,
      }));

    const trainingQueueItems: ManagerApprovalQueueItem[] = teamEnrollments
      .filter((e) => e.status === "pending_approval" && e.employeeId && teamIds.has(e.employeeId))
      .slice(0, TEAM_QUEUE_BOUND)
      .map((e) => ({
        kind: "training_enrollment" as const,
        enrollmentId: e.id,
        employeeId: e.employeeId as string,
        employeeName: nameById.get(e.employeeId as string) ?? e.employeeFullName ?? null,
        summary: `${e.courseName ?? "Training"} — session ${e.sessionCode ?? ""}`.trim(),
        recordVersion: e.recordVersion,
      }));

    return {
      isManager: true,
      team,
      approvalQueue: [...leaveQueueItems, ...overtimeQueueItems, ...timesheetQueueItems, ...trainingQueueItems],
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
