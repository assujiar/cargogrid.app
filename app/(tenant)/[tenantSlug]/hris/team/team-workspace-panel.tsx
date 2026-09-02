"use client";

import { useActionState, useId } from "react";
import { Card } from "../../../../../components/ui/card.tsx";
import { Stat } from "../../../../../components/ui/stat.tsx";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { Link } from "../../../../../components/ui/link.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { MssTeamWorkspace, ManagerApprovalQueueItem } from "../../../../../server/contracts/self-service/self-service.ts";
import type { MssActionState } from "./actions.ts";

const INITIAL_STATE: MssActionState = { error: null };

type BoundAction = (prevState: MssActionState, formData: FormData) => Promise<MssActionState>;

function LeaveQueueForm({ item, action }: { item: Extract<ManagerApprovalQueueItem, { kind: "leave" }>; action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <FormField id={`${reactId}-decision`} label="Decision">
        <Select id={`${reactId}-decision`} name="decision" defaultValue="approved" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="approved">Approve</option>
          <option value="rejected">Reject</option>
        </Select>
      </FormField>
      <FormField id={`${reactId}-reason`} label="Reason (required)">
        <Input type="text" id={`${reactId}-reason`} name="reason" required className="w-56" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Checkbox name="overrideCoverage" label="Override coverage" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Decide
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
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
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2">
      <FormField id={`${reactId}-decision`} label="Decision">
        <Select id={`${reactId}-decision`} name="decision" defaultValue="approve" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="approve">Approve</option>
          <option value="reject">Reject</option>
        </Select>
      </FormField>
      <FormField id={`${reactId}-reason`} label={`Reason${reasonFieldName === "decidedReason" ? " (required)" : ""}`}>
        <Input type="text" id={`${reactId}-reason`} name={reasonFieldName} required={reasonFieldName === "decidedReason"} className="w-56" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      {showMinutesOverride ? (
        <FormField id={`${reactId}-approvedMinutesOverride`} label="Approved minutes override">
          <Input type="number" id={`${reactId}-approvedMinutesOverride`} name="approvedMinutesOverride" min={0} className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Decide
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
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

/**
 * ISS-2026-084. The page history is a stack of the employee numbers each page started
 * after, carried in the URL. Forward pushes the current page's last row; Back pops.
 * Building the links here rather than in the page keeps the two halves of the same
 * mechanism -- what the link says and what the reader sees -- in one file.
 */
function pageHref(basePath: string, cursors: readonly string[], queueLimit: number, defaultQueueLimit: number): string {
  const params = new URLSearchParams();
  if (cursors.length > 0) params.set("teamCursors", cursors.join(","));
  if (queueLimit !== defaultQueueLimit) params.set("queue", String(queueLimit));
  const query = params.toString();
  return query ? `${basePath}?${query}` : basePath;
}

export function TeamWorkspacePanel({
  workspace,
  teamQueueBound,
  teamPageSize,
  queueSizes,
  basePath,
  teamCursors,
  decideLeaveAction,
  decideOvertimeAction,
  decideTimesheetAction,
  decideTrainingAction,
}: {
  workspace: MssTeamWorkspace;
  teamQueueBound: number;
  teamPageSize: number;
  queueSizes: readonly number[];
  basePath: string;
  teamCursors: readonly string[];
  decideLeaveAction: (requestStepId: string) => BoundAction;
  decideOvertimeAction: (requestId: string, expectedVersion: number) => BoundAction;
  decideTimesheetAction: (entryId: string, expectedVersion: number) => BoundAction;
  decideTrainingAction: (enrollmentId: string, expectedVersion: number) => BoundAction;
}) {
  const pageNumber = teamCursors.length + 1;
  const nextCursors = workspace.nextTeamCursor ? [...teamCursors, workspace.nextTeamCursor] : null;
  const previousCursors = teamCursors.length > 0 ? teamCursors.slice(0, -1) : null;

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-lg font-semibold text-text-primary">My team</h1>

      <Card title={`Team roster (${workspace.team.length})`}>
        {/* Before ISS-2026-084 this banner ended "contact HR to see the rest of your
            team" -- an honest disclosure of a boundary, and an instruction to leave the
            product to cross it. The cursor to cross it existed the whole time. */}
        {workspace.teamTruncated || pageNumber > 1 ? (
          <p className="mb-2 text-xs text-neutral-500">
            Page {pageNumber}, {workspace.team.length} of your direct reports, ordered by employee number, {teamPageSize} per page.
          </p>
        ) : null}
        <ul className="flex flex-wrap gap-2 text-sm">
          {workspace.team.map((t) => (
            <li key={t.masterRecordId} className="rounded-full bg-neutral-100 px-3 py-1">
              {t.fullName} <span className="text-neutral-500">({t.employeeNumber})</span>
            </li>
          ))}
        </ul>
        {workspace.team.length === 0 ? <p className="text-sm text-neutral-500">No direct reports on this page.</p> : null}
        {previousCursors || nextCursors ? (
          <nav aria-label="Team roster pages" className="mt-3 flex flex-wrap items-center gap-3 text-xs">
            {previousCursors ? (
              <Link href={pageHref(basePath, previousCursors, workspace.queueLimit, teamQueueBound)} className="underline">
                ← Previous {teamPageSize}
              </Link>
            ) : null}
            {nextCursors ? (
              <Link href={pageHref(basePath, nextCursors, workspace.queueLimit, teamQueueBound)} className="underline">
                Next {teamPageSize} →
              </Link>
            ) : null}
            {pageNumber > 1 ? (
              <Link href={pageHref(basePath, [], workspace.queueLimit, teamQueueBound)} className="text-neutral-500 underline">
                Back to the first page
              </Link>
            ) : null}
          </nav>
        ) : null}
      </Card>

      <Card title={`Approvals (${workspace.approvalQueue.length})`}>
        {/* The size control reports the bound this result was actually built with
            (`workspace.queueLimit`), never the requested one -- the query layer clamps,
            so a banner quoting the request could claim a page size that was not used. */}
        {workspace.approvalQueueTruncated ? (
          <p className="mb-2 text-xs text-warning">
            Showing up to {workspace.queueLimit} pending items per category, and at least one category has more.
          </p>
        ) : null}
        <p className="mb-2 flex flex-wrap items-center gap-2 text-xs text-neutral-500">
          <span>Items per category:</span>
          {queueSizes.map((size) =>
            size === workspace.queueLimit ? (
              <span key={size} aria-current="true" className="rounded bg-neutral-200 px-2 py-1 font-medium text-neutral-900">
                {size}
              </span>
            ) : (
              <Link key={size} href={pageHref(basePath, teamCursors, size, teamQueueBound)} className="rounded px-2 py-1 underline">
                {size}
              </Link>
            ),
          )}
        </p>
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
