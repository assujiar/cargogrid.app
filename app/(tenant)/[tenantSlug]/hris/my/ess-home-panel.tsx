import { Card } from "../../../../../components/ui/card.tsx";
import { Stat } from "../../../../../components/ui/stat.tsx";
import { Link } from "../../../../../components/ui/link.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import type { EssHomeSummary } from "../../../../../server/contracts/self-service/self-service.ts";

/** Server-rendered (no client state) -- every action here is a `Link` to the owning capability's own already-`VERIFIED`/`COMPLETED` page, never a duplicated form. */
export function EssHomePanel({ summary, tenantSlug }: { readonly summary: EssHomeSummary; readonly tenantSlug: string }) {
  const base = `/${tenantSlug}/hris`;

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-lg font-semibold text-text-primary">My workspace</h1>

      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        <Card title="Attendance and schedule">
          <div className="flex flex-col gap-3">
            <div className="flex items-center justify-between">
              <Stat label="Today" value={summary.attendanceToday.status ? summary.attendanceToday.status : "No session"} />
              <StatusBadge tone={summary.attendanceToday.clockedIn ? "success" : "neutral"} label={summary.attendanceToday.clockedIn ? "Clocked in" : "Not clocked in"} />
            </div>
            {summary.attendanceToday.openExceptionCount > 0 ? (
              <p className="text-xs text-warning">{summary.attendanceToday.openExceptionCount} open attendance exception(s)</p>
            ) : null}
            <Stat label="Upcoming shifts (14 days)" value={String(summary.upcomingScheduleCount)} />
            <div className="flex flex-wrap gap-3 text-sm">
              <Link href={`${base}/my/attendance`}>Attendance</Link>
              <Link href={`${base}/my/schedule`}>Schedule</Link>
            </div>
          </div>
        </Card>

        <Card title="Leave and overtime">
          <div className="flex flex-col gap-3">
            <Stat label="Pending leave requests" value={String(summary.pendingLeaveRequestCount)} />
            <Stat label="Pending overtime requests" value={String(summary.pendingOvertimeRequestCount)} />
            <Stat label="Pending timesheet entries" value={String(summary.pendingTimesheetEntryCount)} />
            <div className="flex flex-wrap gap-3 text-sm">
              <Link href={`${base}/my/leave`}>Leave</Link>
              <Link href={`${base}/my/overtime-timesheet`}>Overtime and timesheet</Link>
            </div>
          </div>
        </Card>

        <Card title="Payslip and benefit">
          <div className="flex flex-col gap-3">
            {summary.latestPayslip ? (
              <Stat label="Latest payslip" value={`${summary.latestPayslip.currency} ${summary.latestPayslip.netPay}`} />
            ) : (
              <p className="text-sm text-text-secondary">No payslip yet.</p>
            )}
            <Stat label="Pending reimbursements" value={String(summary.pendingReimbursementCount)} />
            <Stat label="Active loans" value={String(summary.activeLoanCount)} />
            <div className="flex flex-wrap gap-3 text-sm">
              <Link href={`${base}/my/payroll`}>Payroll</Link>
            </div>
          </div>
        </Card>

        <Card title="Performance">
          <div className="flex flex-col gap-3">
            <Stat label="Current goals" value={String(summary.myGoalCount)} />
            {summary.myPendingOutcomeAcknowledgementCount > 0 ? (
              <p className="text-xs text-warning">{summary.myPendingOutcomeAcknowledgementCount} outcome(s) awaiting your acknowledgement</p>
            ) : null}
            {summary.myAssignedTalentReviewCount > 0 ? <Stat label="Assigned talent reviews" value={String(summary.myAssignedTalentReviewCount)} /> : null}
            <div className="flex flex-wrap gap-3 text-sm">
              <Link href={`${base}/my/kpi-performance`}>Goals and reviews</Link>
            </div>
          </div>
        </Card>

        <Card title="Training and development">
          <div className="flex flex-col gap-3">
            <Stat label="Enrolled sessions" value={String(summary.myEnrolledTrainingCount)} />
            {summary.myPendingTrainingApprovalCount > 0 ? <Stat label="Awaiting approval" value={String(summary.myPendingTrainingApprovalCount)} /> : null}
            <Stat label="Active development plans" value={String(summary.myActiveDevelopmentPlanCount)} />
            <div className="flex flex-wrap gap-3 text-sm">
              <Link href={`${base}/my/training-talent`}>Training and talent</Link>
            </div>
          </div>
        </Card>

        <Card title="Profile">
          <div className="flex flex-col gap-3">
            <p className="text-sm text-text-secondary">View your own record and request a correction.</p>
            <div className="flex flex-wrap gap-3 text-sm">
              <Link href={`${base}/my/profile`}>My profile</Link>
            </div>
          </div>
        </Card>
      </div>

      <div className="text-sm">
        <Link href={`${base}/team`}>Go to my team workspace (managers)</Link>
      </div>
    </div>
  );
}
