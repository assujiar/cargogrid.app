"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import { Timeline, type ActivityItemData } from "../../../../../../components/ui/timeline.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { OnboardingCaseActionState } from "./actions.ts";
import type { CaseDetail, CaseTask, ApprovalTimelineRow, CaseStatus, TaskStatus, ApprovalDecision } from "../../../../../../server/contracts/onboarding/onboarding.ts";

const INITIAL_STATE: OnboardingCaseActionState = { error: null };

type BoundAction = (prevState: OnboardingCaseActionState, formData: FormData) => Promise<OnboardingCaseActionState>;
type TaskBoundAction = (taskId: string, expectedVersion: number) => BoundAction;

const CASE_STATUS_TONE: Record<CaseStatus, StatusTone> = {
  draft: "neutral",
  active: "info",
  pending_finalize_approval: "warning",
  finalized: "success",
  cancelled: "danger",
};

const TASK_STATUS_TONE: Record<TaskStatus, StatusTone> = {
  pending: "neutral",
  blocked: "warning",
  in_progress: "info",
  completed: "success",
  waived: "neutral",
  reopened: "warning",
};

export function CaseDetailPanel({
  tenantSlug,
  caseDetail,
  tasks,
  timeline,
  employeeLifecycleStatus,
  assignTaskAction,
  completeTaskAction,
  waiveTaskAction,
  reopenTaskAction,
  requestProvisioningAction,
  requestRevocationAction,
  submitFinalizeApprovalAction,
  decideFinalizeApprovalAction,
  cancelCaseAction,
  rehireEmployeeAction,
}: {
  tenantSlug: string;
  caseDetail: CaseDetail;
  tasks: readonly CaseTask[];
  timeline: readonly ApprovalTimelineRow[];
  employeeLifecycleStatus: string | null;
  assignTaskAction: TaskBoundAction;
  completeTaskAction: TaskBoundAction;
  waiveTaskAction: TaskBoundAction;
  reopenTaskAction: TaskBoundAction;
  requestProvisioningAction: TaskBoundAction;
  requestRevocationAction: TaskBoundAction;
  submitFinalizeApprovalAction: BoundAction;
  decideFinalizeApprovalAction: (requestStepId: string, decision: ApprovalDecision) => BoundAction;
  cancelCaseAction: BoundAction;
  rehireEmployeeAction: BoundAction | null;
}) {
  const [submitState, submitFormAction, submitPending] = useActionState(submitFinalizeApprovalAction, INITIAL_STATE);
  const [cancelState, cancelFormAction, cancelPending] = useActionState(cancelCaseAction, INITIAL_STATE);
  const [rehireState, rehireFormAction, rehirePending] = useActionState(rehireEmployeeAction ?? (async (_s: OnboardingCaseActionState) => INITIAL_STATE), INITIAL_STATE);

  const mandatoryIncomplete = tasks.filter((t) => t.isMandatory && t.status !== "completed" && t.status !== "waived").length;
  const pendingStep = timeline.find((row) => row.stepStatus === "active");
  const canCancel = caseDetail.status === "draft" || caseDetail.status === "active" || caseDetail.status === "pending_finalize_approval";
  const canSubmitFinalize = caseDetail.status === "active";

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">
            {caseDetail.employeeFullName ?? "(unlinked employee)"} — {caseDetail.caseType}
          </h1>
          <div className="mt-1 flex flex-wrap items-center gap-2 text-xs text-neutral-500">
            <StatusBadge tone={CASE_STATUS_TONE[caseDetail.status]} label={caseDetail.status.replace(/_/g, " ")} />
            <span>Source: {caseDetail.sourceType.replace(/_/g, " ")}</span>
            {caseDetail.effectiveDate ? <span>Effective {caseDetail.effectiveDate}</span> : null}
            {caseDetail.employeeMasterRecordId ? (
              <Link href={`/${tenantSlug}/hris/employees/${caseDetail.employeeMasterRecordId}`} className="text-primary underline">
                View employee profile
              </Link>
            ) : null}
          </div>
        </div>
        {canCancel ? (
          <form action={cancelFormAction} className="flex items-end gap-2">
            <FormField id="cancel-reason" label="Cancel reason">
              <Input id="cancel-reason" name="reason" type="text" required invalid={Boolean(cancelState.error)} aria-describedby={cancelState.error ? "cancel-case-error" : undefined} />
            </FormField>
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">
              Cancel case
            </Button>
          </form>
        ) : null}
      </div>
      {cancelState.error ? <ValidationMessage id="cancel-case-error">{cancelState.error}</ValidationMessage> : null}

      {caseDetail.status === "cancelled" && caseDetail.cancelReason ? (
        <div className="rounded-md border border-neutral-200 bg-neutral-50 p-3 text-sm text-neutral-700">Cancelled: {caseDetail.cancelReason}</div>
      ) : null}
      {caseDetail.exitReasonMasked ? (
        <div className="rounded-md border border-neutral-200 bg-neutral-50 p-3 text-xs text-neutral-500">Exit reason is on file but restricted -- you do not hold HRS:View personal data.</div>
      ) : caseDetail.exitReason ? (
        <div className="rounded-md border border-neutral-200 bg-neutral-50 p-3 text-sm text-neutral-700">Exit reason: {caseDetail.exitReason}</div>
      ) : null}

      {employeeLifecycleStatus === "terminated" && rehireEmployeeAction ? (
        <section className="flex flex-col gap-2 rounded-md border border-warning/40 bg-warning/5 p-3">
          <p className="text-sm text-neutral-700">This employee is terminated. Rehire (section 22 &quot;rehire linked to historical employee&quot;) requires HRS:Override.</p>
          <form action={rehireFormAction} className="flex flex-wrap items-end gap-2">
            <FormField id="rehire-reason" label="Rehire reason">
              <Input id="rehire-reason" name="reason" type="text" required invalid={Boolean(rehireState.error)} aria-describedby={rehireState.error ? "rehire-error" : undefined} />
            </FormField>
            <Button type="submit" loading={rehirePending} loadingLabel="Rehiring…">
              Rehire employee
            </Button>
          </form>
          {rehireState.error ? <ValidationMessage id="rehire-error">{rehireState.error}</ValidationMessage> : null}
        </section>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Checklist -- access/asset preview and evidence</h2>
        {tasks.length === 0 ? (
          <EmptyState title="No tasks" description="This case has no instantiated checklist tasks." />
        ) : (
          <div className="flex flex-col gap-3">
            {tasks.map((task) => (
              <TaskRow
                key={task.id}
                tenantSlug={tenantSlug}
                task={task}
                allTasks={tasks}
                assignAction={assignTaskAction(task.id, task.recordVersion)}
                completeAction={completeTaskAction(task.id, task.recordVersion)}
                waiveAction={waiveTaskAction(task.id, task.recordVersion)}
                reopenAction={reopenTaskAction(task.id, task.recordVersion)}
                provisionAction={requestProvisioningAction(task.id, task.recordVersion)}
                revokeAction={requestRevocationAction(task.id, task.recordVersion)}
              />
            ))}
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Approval timeline</h2>
        {timeline.length === 0 ? (
          <EmptyState title="No finalize approval submitted yet" description="Submit for finalize approval once every mandatory task is complete or waived." />
        ) : (
          <Timeline items={timeline.map(timelineRowToActivityItem)} />
        )}

        {canSubmitFinalize ? (
          <form action={submitFormAction} className="flex flex-col gap-2 border-t border-neutral-100 pt-3">
            {mandatoryIncomplete > 0 ? <p className="text-xs text-warning">{mandatoryIncomplete} mandatory task(s) still incomplete -- submission will be rejected until they are completed or waived.</p> : null}
            {caseDetail.caseType === "offboarding" ? (
              <FormField id="exitReason" label="Exit reason (required for offboarding)">
                <Input id="exitReason" name="exitReason" type="text" required invalid={Boolean(submitState.error)} aria-describedby={submitState.error ? "submit-finalize-error" : undefined} />
              </FormField>
            ) : null}
            {submitState.error ? <ValidationMessage id="submit-finalize-error">{submitState.error}</ValidationMessage> : null}
            <div>
              <Button type="submit" loading={submitPending} loadingLabel="Submitting…">
                Submit for finalize approval
              </Button>
            </div>
          </form>
        ) : null}

        {caseDetail.status === "pending_finalize_approval" && pendingStep ? <DecisionForm requestStepId={pendingStep.stepId} decideAction={decideFinalizeApprovalAction} /> : null}
      </section>
    </div>
  );
}

function timelineRowToActivityItem(row: ApprovalTimelineRow): ActivityItemData {
  return {
    at: row.decidedAt ?? new Date(0).toISOString(),
    actor: row.actorLabel ?? "(pending decision)",
    event: row.decision ? `${row.decision} step ${row.stepOrder}${row.reason ? ` -- ${row.reason}` : ""}` : `step ${row.stepOrder} ${row.stepStatus}`,
  };
}

function DecisionForm({ requestStepId, decideAction }: { requestStepId: string; decideAction: (requestStepId: string, decision: ApprovalDecision) => BoundAction }) {
  const [approveState, approveFormAction, approvePending] = useActionState(decideAction(requestStepId, "approved"), INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(decideAction(requestStepId, "rejected"), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2 border-t border-neutral-100 pt-3">
      <p className="text-xs text-neutral-500">A decision is awaiting your approval authority on this case.</p>
      <div className="flex flex-wrap gap-2">
        <form action={approveFormAction}>
          <Button type="submit" loading={approvePending} loadingLabel="Approving…">
            Approve finalize
          </Button>
        </form>
        <form action={rejectFormAction} className="flex items-end gap-2">
          <label className="sr-only" htmlFor={`finalize-reject-reason-${requestStepId}`}>
            Rejection reason
          </label>
          <Input
            id={`finalize-reject-reason-${requestStepId}`}
            name="reason"
            type="text"
            placeholder="rejection reason"
            required
            invalid={Boolean(rejectState.error)}
            aria-describedby={rejectState.error ? `finalize-reject-error-${requestStepId}` : undefined}
          />
          <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </form>
      </div>
      {approveState.error ? <ValidationMessage id={`finalize-approve-error-${requestStepId}`}>{approveState.error}</ValidationMessage> : null}
      {rejectState.error ? <ValidationMessage id={`finalize-reject-error-${requestStepId}`}>{rejectState.error}</ValidationMessage> : null}
    </div>
  );
}

function TaskRow({
  tenantSlug,
  task,
  allTasks,
  assignAction,
  completeAction,
  waiveAction,
  reopenAction,
  provisionAction,
  revokeAction,
}: {
  tenantSlug: string;
  task: CaseTask;
  allTasks: readonly CaseTask[];
  assignAction: BoundAction;
  completeAction: BoundAction;
  waiveAction: BoundAction;
  reopenAction: BoundAction;
  provisionAction: BoundAction;
  revokeAction: BoundAction;
}) {
  const [assignState, assignFormAction, assignPending] = useActionState(assignAction, INITIAL_STATE);
  const [completeState, completeFormAction, completePending] = useActionState(completeAction, INITIAL_STATE);
  const [waiveState, waiveFormAction, waivePending] = useActionState(waiveAction, INITIAL_STATE);
  const [reopenState, reopenFormAction, reopenPending] = useActionState(reopenAction, INITIAL_STATE);
  const [provisionState, provisionFormAction, provisionPending] = useActionState(provisionAction, INITIAL_STATE);
  const [revokeState, revokeFormAction, revokePending] = useActionState(revokeAction, INITIAL_STATE);

  const isTerminal = task.status === "completed" || task.status === "waived";
  const isBlocked = task.status === "blocked";
  const dependencyTitles = task.dependsOnTaskIds.map((id) => allTasks.find((t) => t.id === id)?.title ?? id);

  return (
    <div className="rounded-md border border-neutral-100 p-3">
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div>
          <p className="text-sm font-medium text-neutral-900">
            {task.title} {task.isMandatory ? <span className="text-xs text-neutral-400">(mandatory)</span> : <span className="text-xs text-neutral-400">(optional)</span>}
          </p>
          <p className="text-xs text-neutral-500">
            {task.taskType.replace(/_/g, " ")}
            {task.handoffCategory ? ` — ${task.handoffCategory}` : ""} · owner: {task.ownerType}
            {task.dueAt ? ` · due ${new Date(task.dueAt).toLocaleDateString()}` : ""}
          </p>
          {dependencyTitles.length > 0 ? <p className="text-xs text-neutral-400">Depends on: {dependencyTitles.join(", ")}</p> : null}
        </div>
        <div className="flex items-center gap-2">
          {task.isOverdue ? <StatusBadge tone="danger" label="overdue" /> : null}
          <StatusBadge tone={TASK_STATUS_TONE[task.status]} label={task.status.replace(/_/g, " ")} />
        </div>
      </div>

      {task.evidenceNote || task.evidenceFileId || task.sensitiveMasked ? (
        <p className="mt-1 text-xs text-neutral-600">
          Evidence: {task.sensitiveMasked ? "restricted (no View personal data)" : (task.evidenceNote ?? "—")}
          {task.evidenceFileId ? ` (file attached)` : ""}
        </p>
      ) : null}
      {task.waiveReason ? <p className="text-xs text-neutral-600">Waive reason: {task.sensitiveMasked ? "restricted" : task.waiveReason}</p> : null}

      {!isTerminal && !isBlocked ? (
        <div className="mt-2 flex flex-col gap-2">
          <form action={assignFormAction} className="flex flex-wrap items-end gap-2">
            <FormField id={`task-owner-${task.id}`} label="Assign owner (auth user id)">
              <Input
                id={`task-owner-${task.id}`}
                name="ownerAuthUserId"
                type="text"
                defaultValue={task.ownerAuthUserId ?? ""}
                invalid={Boolean(assignState.error)}
                aria-describedby={assignState.error ? `task-assign-error-${task.id}` : undefined}
              />
            </FormField>
            <Button type="submit" variant="secondary" loading={assignPending} loadingLabel="Assigning…">
              Assign
            </Button>
          </form>
          {assignState.error ? <ValidationMessage id={`task-assign-error-${task.id}`}>{assignState.error}</ValidationMessage> : null}

          {task.taskType === "access_provisioning" ? (
            <form action={provisionFormAction} className="flex flex-wrap items-end gap-2 rounded-md bg-neutral-50 p-2">
              <FormField id={`task-target-user-${task.id}`} label="Target auth user id (resolved identity, optional)">
                <Input
                  id={`task-target-user-${task.id}`}
                  name="targetAuthUserId"
                  type="text"
                  placeholder="leave blank to only record the request"
                  invalid={Boolean(provisionState.error)}
                  aria-describedby={provisionState.error ? `task-provision-error-${task.id}` : undefined}
                />
              </FormField>
              <FormField id={`task-role-versions-${task.id}`} label="Role version ids (comma-separated, optional)">
                <Input
                  id={`task-role-versions-${task.id}`}
                  name="roleVersionIds"
                  type="text"
                  invalid={Boolean(provisionState.error)}
                  aria-describedby={provisionState.error ? `task-provision-error-${task.id}` : undefined}
                />
              </FormField>
              <Button type="submit" loading={provisionPending} loadingLabel="Requesting…">
                Request provisioning
              </Button>
            </form>
          ) : task.taskType === "access_revocation" ? (
            <form action={revokeFormAction} className="flex flex-wrap items-end gap-2 rounded-md bg-neutral-50 p-2">
              <FormField id={`task-revoke-reason-${task.id}`} label="Reason (required)">
                <Input
                  id={`task-revoke-reason-${task.id}`}
                  name="reason"
                  type="text"
                  required
                  invalid={Boolean(revokeState.error)}
                  aria-describedby={revokeState.error ? `task-revoke-error-${task.id}` : undefined}
                />
              </FormField>
              <Button type="submit" variant="destructive" loading={revokePending} loadingLabel="Revoking…">
                Request revocation
              </Button>
            </form>
          ) : (
            <form action={completeFormAction} className="flex flex-wrap items-end gap-2">
              <FormField id={`task-evidence-note-${task.id}`} label={`Evidence note${task.taskType === "handoff" ? " (a note or a file is required)" : ""}`}>
                <Input
                  id={`task-evidence-note-${task.id}`}
                  name="evidenceNote"
                  type="text"
                  invalid={Boolean(completeState.error)}
                  aria-describedby={completeState.error ? `task-complete-error-${task.id}` : undefined}
                />
              </FormField>
              <FormField id={`task-evidence-file-${task.id}`} label="Evidence file id (optional)">
                <Input
                  id={`task-evidence-file-${task.id}`}
                  name="evidenceFileId"
                  type="text"
                  invalid={Boolean(completeState.error)}
                  aria-describedby={completeState.error ? `task-complete-error-${task.id}` : undefined}
                />
              </FormField>
              <Button type="submit" loading={completePending} loadingLabel="Completing…">
                Complete
              </Button>
            </form>
          )}
          {provisionState.error ? <ValidationMessage id={`task-provision-error-${task.id}`}>{provisionState.error}</ValidationMessage> : null}
          {revokeState.error ? <ValidationMessage id={`task-revoke-error-${task.id}`}>{revokeState.error}</ValidationMessage> : null}
          {completeState.error ? <ValidationMessage id={`task-complete-error-${task.id}`}>{completeState.error}</ValidationMessage> : null}

          <form action={waiveFormAction} className="flex flex-wrap items-end gap-2">
            <FormField id={`task-waive-reason-${task.id}`} label="Waive reason">
              <Input
                id={`task-waive-reason-${task.id}`}
                name="waiveReason"
                type="text"
                invalid={Boolean(waiveState.error)}
                aria-describedby={waiveState.error ? `task-waive-error-${task.id}` : undefined}
              />
            </FormField>
            <Button type="submit" variant="secondary" loading={waivePending} loadingLabel="Waiving…">
              Waive (requires Override)
            </Button>
          </form>
          {waiveState.error ? <ValidationMessage id={`task-waive-error-${task.id}`}>{waiveState.error}</ValidationMessage> : null}
        </div>
      ) : isBlocked ? (
        <p className="mt-2 text-xs text-warning">Blocked -- waiting on the task(s) listed above.</p>
      ) : (
        <form action={reopenFormAction} className="mt-2 flex flex-wrap items-end gap-2">
          <FormField id={`task-reopen-reason-${task.id}`} label="Reopen reason">
            <Input
              id={`task-reopen-reason-${task.id}`}
              name="reason"
              type="text"
              invalid={Boolean(reopenState.error)}
              aria-describedby={reopenState.error ? `task-reopen-error-${task.id}` : undefined}
            />
          </FormField>
          <Button type="submit" variant="secondary" loading={reopenPending} loadingLabel="Reopening…">
            Reopen
          </Button>
          {reopenState.error ? <ValidationMessage id={`task-reopen-error-${task.id}`}>{reopenState.error}</ValidationMessage> : null}
        </form>
      )}
    </div>
  );
}
