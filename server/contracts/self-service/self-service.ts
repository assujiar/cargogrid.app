/**
 * Employee and Manager Self-Service (ESS/MSS) composition contracts (HRT-285,
 * CG-S12-HRT-013). This capability is a projection and action surface over
 * the already-`VERIFIED`/`COMPLETED` canonical HR services (HRT-278..284) --
 * per Prompt 285 section 13, "no duplicate HR truth". Nothing in this file
 * defines a new persisted table or a new authority check: every type here is
 * either (a) a thin, field-minimized re-shaping of row types already defined
 * and parsed by the OWNING capability's own contracts module (re-imported,
 * never redefined), or (b) a routing envelope for the one genuinely composed
 * write this capability adds -- a single "decide this manager-queue item"
 * action that dispatches to the correct canonical `decide*` mutation by
 * `kind`, so the MSS UI needs exactly one action surface instead of six.
 *
 * Every `decision`/`reason` field below reuses the OWNING capability's own
 * enum schema (imported, not re-declared) -- e.g. leave's decision literals
 * are `"approved"|"rejected"` (past tense) while overtime/timesheet/training
 * use `"approve"|"reject"` (imperative); this file does not paper over that
 * inconsistency, it forwards each capability's own real shape unchanged, so
 * a caller that gets the wrong literal for a given `kind` fails Zod
 * validation before any RPC call, never silently coerces.
 */

import { z } from "zod";
import { ApprovalDecisionSchema } from "../leave/leave.ts";
import { DecisionSchema as OvertimeTimesheetDecisionSchema } from "../overtime-timesheet/overtime-timesheet.ts";
import type {
  OvertimeRequestAdminRow,
  TimesheetEntryAdminRow,
} from "../overtime-timesheet/overtime-timesheet.ts";
import type { LeaveRequestDetail } from "../leave/leave.ts";
import type { ScheduleAssignmentListRow } from "../shift-roster/shift-roster.ts";
import type { PerformanceOutcomeRow, PerformanceGoalAssignmentRow, PerformanceCycleRow } from "../kpi-performance/kpi-performance.ts";
import type { TrainingEnrollmentRow, TrainingCertificateRow } from "../training-talent/training-talent.ts";
import type { MyTeamEmployeeRow } from "../employee/employee.ts";

// --- ESS home ---

/** Bounded, count-first summary -- never a full list of any underlying capability's rows (section 17: "bounded server composition... no client fan-out across full HR datasets"). Every field here is either a count or a short, capped array of the caller's OWN rows (each already self-scoped by the owning capability's own `my_*`/self-resolving RPC -- never a client-supplied employee id anywhere in this file). */
export interface EssHomeSummary {
  readonly hasEmployeeProfile: boolean;
  readonly attendanceToday: {
    readonly status: string | null;
    readonly clockedIn: boolean;
    readonly openExceptionCount: number;
  };
  readonly upcomingScheduleCount: number;
  readonly pendingLeaveRequestCount: number;
  readonly pendingOvertimeRequestCount: number;
  readonly pendingTimesheetEntryCount: number;
  readonly latestPayslip: { readonly payslipId: string; readonly currency: string; readonly netPay: string } | null;
  readonly pendingReimbursementCount: number;
  readonly activeLoanCount: number;
  readonly myGoalCount: number;
  readonly myPendingOutcomeAcknowledgementCount: number;
  readonly myEnrolledTrainingCount: number;
  readonly myPendingTrainingApprovalCount: number;
  readonly myActiveDevelopmentPlanCount: number;
  readonly myAssignedTalentReviewCount: number;
}

// --- MSS team workspace ---

/** One entry in the manager's unified approval queue -- a discriminated union so the UI can render each kind's own summary text without knowing the owning capability's schema, while `decide` (below) still routes to that capability's own canonical mutation, never a shortcut. */
export type ManagerApprovalQueueItem =
  | {
      readonly kind: "leave";
      readonly requestStepId: string;
      readonly leaveRequestId: string;
      readonly employeeId: string;
      readonly employeeName: string | null;
      readonly summary: string;
      readonly recordVersion: number;
    }
  | {
      readonly kind: "overtime";
      readonly requestId: string;
      readonly employeeId: string;
      readonly employeeName: string | null;
      readonly summary: string;
      readonly recordVersion: number;
    }
  | {
      readonly kind: "timesheet_entry";
      readonly entryId: string;
      readonly employeeId: string;
      readonly employeeName: string | null;
      readonly summary: string;
      readonly recordVersion: number;
    }
  | {
      readonly kind: "training_enrollment";
      readonly enrollmentId: string;
      readonly employeeId: string;
      readonly employeeName: string | null;
      readonly summary: string;
      readonly recordVersion: number;
    };

export interface MssTeamWorkspace {
  readonly isManager: boolean;
  readonly team: readonly MyTeamEmployeeRow[];
  readonly approvalQueue: readonly ManagerApprovalQueueItem[];
  readonly teamScheduleUpcoming: readonly ScheduleAssignmentListRow[];
  readonly currentPerformanceCycle: PerformanceCycleRow | null;
  readonly teamGoalAssignments: readonly PerformanceGoalAssignmentRow[];
  readonly teamOutcomes: readonly PerformanceOutcomeRow[];
  readonly teamTrainingEnrollments: readonly TrainingEnrollmentRow[];
  readonly teamCertificates: readonly TrainingCertificateRow[];
}

// --- Composed decide action ---

const LeaveApprovalDecisionSchema = ApprovalDecisionSchema; // "approved" | "rejected"
const ImperativeDecisionSchema = OvertimeTimesheetDecisionSchema; // "approve" | "reject"

export const DecideManagerApprovalQueueItemInputSchema = z.discriminatedUnion("kind", [
  z.object({
    kind: z.literal("leave"),
    requestStepId: z.string().uuid(),
    decision: LeaveApprovalDecisionSchema,
    reason: z.string().min(1),
    overrideCoverage: z.boolean(),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string(),
  }),
  z.object({
    kind: z.literal("overtime"),
    requestId: z.string().uuid(),
    expectedVersion: z.number().int().positive(),
    decision: ImperativeDecisionSchema,
    decidedReason: z.string().min(1),
    approvedMinutesOverride: z.number().int().nonnegative().nullable(),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string(),
  }),
  z.object({
    kind: z.literal("timesheet_entry"),
    entryId: z.string().uuid(),
    expectedVersion: z.number().int().positive(),
    decision: ImperativeDecisionSchema,
    decidedReason: z.string().min(1),
    approvedMinutesOverride: z.number().int().nonnegative().nullable(),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string(),
  }),
  z.object({
    kind: z.literal("training_enrollment"),
    enrollmentId: z.string().uuid(),
    expectedVersion: z.number().int().positive(),
    decision: z.enum(["approve", "reject"]),
    decisionReason: z.string().nullable(),
    actorAuthUserId: z.string().uuid(),
    actorLabel: z.string(),
  }),
]);
export type DecideManagerApprovalQueueItemInput = z.infer<typeof DecideManagerApprovalQueueItemInputSchema>;

/** Deliberately minimal (echoes only what the caller already knows) rather than re-shaping each owning capability's own heterogeneous raw RPC-return casing (leave/overtime/timesheet mutations return an unparsed `Record<string, unknown>` snake_case row; training's own mutation DOES parse to a typed row). The UI re-fetches `getMssTeamWorkspace` (via `revalidatePath`) for the authoritative post-decision state rather than trusting a hand-normalized echo. */
export interface DecideManagerApprovalQueueItemResult {
  readonly kind: DecideManagerApprovalQueueItemInput["kind"];
  readonly id: string;
}

// Re-exported so callers of this composition layer never need to reach into
// an owning capability's own contracts module just to render a queue item.
export type { LeaveRequestDetail, OvertimeRequestAdminRow, TimesheetEntryAdminRow };
