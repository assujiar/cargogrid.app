"use client";

import { useActionState } from "react";
import { Card } from "../../../../../components/ui/card.tsx";
import { Stat } from "../../../../../components/ui/stat.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { MssTeamWorkspace, ManagerApprovalQueueItem } from "../../../../../server/contracts/self-service/self-service.ts";
import type { MssActionState } from "./actions.ts";

const INITIAL_STATE: MssActionState = { error: null };

type BoundAction = (prevState: MssActionState, formData: FormData) => Promise<MssActionState>;

function ErrorLine({ error }: { error: string | null }) {
  return error ? (
    <p role="alert" className="text-xs text-danger">
      {error}
    </p>
  ) : null;
}

function LeaveQueueForm({ item, action }: { item: Extract<ManagerApprovalQueueItem, { kind: "leave" }>; action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <label className="text-xs text-neutral-500">
        Decision
        <select name="decision" defaultValue="approved" className="mt-1 block rounded border border-neutral-300 p-1 text-sm">
          <option value="approved">Approve</option>
          <option value="rejected">Reject</option>
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Reason (required)
        <input type="text" name="reason" required className="mt-1 block w-56 rounded border border-neutral-300 p-1 text-sm" />
      </label>
      <label className="flex items-center gap-1 text-xs text-neutral-500">
        <input type="checkbox" name="overrideCoverage" /> Override coverage
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Decide
      </Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function ImperativeQueueForm({
  action,
  reasonFieldName,
  showMinutesOverride,
}: {
  action: BoundAction;
  reasonFieldName: "decidedReason" | "decisionReason";
  showMinutesOverride: boolean;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <label className="text-xs text-neutral-500">
        Decision
        <select name="decision" defaultValue="approve" className="mt-1 block rounded border border-neutral-300 p-1 text-sm">
          <option value="approve">Approve</option>
          <option value="reject">Reject</option>
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Reason{reasonFieldName === "decidedReason" ? " (required)" : ""}
        <input type="text" name={reasonFieldName} required={reasonFieldName === "decidedReason"} className="mt-1 block w-56 rounded border border-neutral-300 p-1 text-sm" />
      </label>
      {showMinutesOverride ? (
        <label className="text-xs text-neutral-500">
          Approved minutes override
          <input type="number" name="approvedMinutesOverride" min={0} className="mt-1 block w-32 rounded border border-neutral-300 p-1 text-sm" />
        </label>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Decide
      </Button>
      <ErrorLine error={state.error} />
    </form>
  );
}

function QueueItemRow({
  item,
  decideLeaveAction,
  decideOvertimeAction,
  decideTimesheetAction,
  decideTrainingAction,
}: {
  item: ManagerApprovalQueueItem;
  decideLeaveAction: (requestStepId: string) => BoundAction;
  decideOvertimeAction: (requestId: string, expectedVersion: number) => BoundAction;
  decideTimesheetAction: (entryId: string, expectedVersion: number) => BoundAction;
  decideTrainingAction: (enrollmentId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span className="font-medium">{item.employeeName ?? "Team member"}</span>
        <StatusBadge tone="warning" label={item.kind.replace(/_/g, " ")} />
      </div>
      <p className="text-neutral-600">{item.summary}</p>
      {item.kind === "leave" ? (
        <LeaveQueueForm item={item} action={decideLeaveAction(item.requestStepId)} />
      ) : item.kind === "overtime" ? (
        <ImperativeQueueForm action={decideOvertimeAction(item.requestId, item.recordVersion)} reasonFieldName="decidedReason" showMinutesOverride />
      ) : item.kind === "timesheet_entry" ? (
        <ImperativeQueueForm action={decideTimesheetAction(item.entryId, item.recordVersion)} reasonFieldName="decidedReason" showMinutesOverride />
      ) : (
        <ImperativeQueueForm action={decideTrainingAction(item.enrollmentId, item.recordVersion)} reasonFieldName="decisionReason" showMinutesOverride={false} />
      )}
    </li>
  );
}

const OUTCOME_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral", published: "info", acknowledged: "success", appealed: "warning", reopened: "warning", closed: "success",
};

export function TeamWorkspacePanel({
  workspace,
  teamQueueBound,
  decideLeaveAction,
  decideOvertimeAction,
  decideTimesheetAction,
  decideTrainingAction,
}: {
  workspace: MssTeamWorkspace;
  teamQueueBound: number;
  decideLeaveAction: (requestStepId: string) => BoundAction;
  decideOvertimeAction: (requestId: string, expectedVersion: number) => BoundAction;
  decideTimesheetAction: (entryId: string, expectedVersion: number) => BoundAction;
  decideTrainingAction: (enrollmentId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-lg font-semibold text-text-primary">My team</h1>

      <Card title={`Team roster (${workspace.team.length})`}>
        {workspace.teamTruncated ? (
          <p className="mb-2 text-xs text-warning">Showing the first {workspace.team.length} direct reports. You have more than that — contact HR to see the rest of your team.</p>
        ) : null}
        <ul className="flex flex-wrap gap-2 text-sm">
          {workspace.team.map((t) => (
            <li key={t.masterRecordId} className="rounded-full bg-neutral-100 px-3 py-1">
              {t.fullName} <span className="text-neutral-500">({t.employeeNumber})</span>
            </li>
          ))}
        </ul>
      </Card>

      <Card title={`Approvals (${workspace.approvalQueue.length})`}>
        {workspace.approvalQueueTruncated ? (
          <p className="mb-2 text-xs text-warning">Showing up to {teamQueueBound} pending items per category. More may be waiting — check each capability&apos;s own admin workspace for the full queue.</p>
        ) : null}
        {workspace.approvalQueue.length === 0 ? (
          <EmptyState title="Nothing pending" description="No approvals are waiting for your effective team." />
        ) : (
          <ul className="flex flex-col gap-2">
            {workspace.approvalQueue.map((item) => (
              <QueueItemRow
                key={`${item.kind}-${"requestStepId" in item ? item.requestStepId : "requestId" in item ? item.requestId : "entryId" in item ? item.entryId : item.enrollmentId}`}
                item={item}
                decideLeaveAction={decideLeaveAction}
                decideOvertimeAction={decideOvertimeAction}
                decideTimesheetAction={decideTimesheetAction}
                decideTrainingAction={decideTrainingAction}
              />
            ))}
          </ul>
        )}
      </Card>

      <Card title={`Team schedule, next 14 days (${workspace.teamScheduleUpcoming.length})`}>
        {workspace.teamScheduleUpcoming.length === 0 ? (
          <p className="text-sm text-text-secondary">No upcoming assignments.</p>
        ) : (
          <ul className="flex flex-col gap-1 text-sm">
            {workspace.teamScheduleUpcoming.slice(0, 20).map((a) => (
              <li key={a.id} className="flex items-center justify-between">
                <span>
                  {a.employeeFullName} — {a.workDate} ({a.shiftTemplateName})
                </span>
                <StatusBadge tone={a.status === "published" ? "success" : "neutral"} label={a.status} />
              </li>
            ))}
          </ul>
        )}
      </Card>

      <Card title="Team performance summary">
        {!workspace.currentPerformanceCycle ? (
          <p className="text-sm text-text-secondary">No performance cycle to summarize.</p>
        ) : (
          <div className="flex flex-col gap-3">
            <Stat label={workspace.currentPerformanceCycle.name} value={workspace.currentPerformanceCycle.status.replace(/_/g, " ")} />
            <Stat label="Goals assigned (team)" value={String(workspace.teamGoalAssignments.length)} />
            {workspace.teamOutcomes.length > 0 ? (
              <ul className="flex flex-col gap-1 text-sm">
                {workspace.teamOutcomes.map((o) => (
                  <li key={o.id} className="flex items-center justify-between">
                    <span>{o.employeeFullName}</span>
                    <span className="flex items-center gap-2">
                      {o.finalScore ? <span>{o.finalScore}</span> : null}
                      <StatusBadge tone={OUTCOME_STATUS_TONE[o.status] ?? "neutral"} label={o.status} />
                    </span>
                  </li>
                ))}
              </ul>
            ) : (
              <p className="text-sm text-text-secondary">No published outcomes yet for this cycle.</p>
            )}
          </div>
        )}
      </Card>

      <Card title="Team training status">
        <div className="flex flex-col gap-3">
          <Stat label="Enrollments (team)" value={String(workspace.teamTrainingEnrollments.length)} />
          {workspace.teamTrainingEnrollments.length > 0 ? (
            <ul className="flex flex-col gap-1 text-sm">
              {workspace.teamTrainingEnrollments.slice(0, 20).map((e) => (
                <li key={e.id} className="flex items-center justify-between">
                  <span>
                    {e.employeeFullName ?? "—"} — {e.courseName ?? "Training"}
                  </span>
                  <StatusBadge tone={e.status === "completed" ? "success" : e.status === "failed" ? "danger" : "neutral"} label={e.status.replace(/_/g, " ")} />
                </li>
              ))}
            </ul>
          ) : null}
          <Stat label="Certificates (team)" value={String(workspace.teamCertificates.length)} />
          {workspace.teamCertificates.filter((c) => c.status === "expired").length > 0 ? (
            <p className="text-xs text-warning">{workspace.teamCertificates.filter((c) => c.status === "expired").length} expired certificate(s)</p>
          ) : null}
        </div>
      </Card>
    </div>
  );
}
