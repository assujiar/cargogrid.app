"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { LeaveRequestListRow } from "../../../../../server/contracts/leave/leave.ts";
import type { LeaveApprovalInboxItem } from "../../../../../server/queries/leave.ts";
import type { LeaveAdminActionState } from "./actions.ts";

type BoundAction = (prevState: LeaveAdminActionState, formData: FormData) => Promise<LeaveAdminActionState>;

const INITIAL_STATE: LeaveAdminActionState = { error: null };
const REQUEST_STATUS_TONE: Record<string, StatusTone> = {
  draft: "neutral",
  pending_approval: "warning",
  approved: "success",
  rejected: "danger",
  cancelled: "neutral",
};

function InboxItemRow({ item, decideAction }: { item: LeaveApprovalInboxItem; decideAction: (requestStepId: string, decision: "approved" | "rejected") => BoundAction }) {
  const [approveState, approveFormAction, approvePending] = useActionState(decideAction(item.stepId, "approved"), INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(decideAction(item.stepId, "rejected"), INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <span className="text-sm">
        Leave request <span className="font-mono text-xs">{item.leaveRequestId}</span> — step {item.stepOrder}
      </span>
      <form action={approveFormAction} className="flex flex-wrap items-center gap-2">
        <label htmlFor={`approve-reason-${item.stepId}`} className="sr-only">
          Decision reason
        </label>
        <Input
          id={`approve-reason-${item.stepId}`}
          name="reason"
          required
          placeholder="Decision reason (required)"
          className="min-w-[10rem] flex-1 text-xs"
          invalid={Boolean(approveState.error)}
          aria-describedby={approveState.error ? `approve-${item.stepId}-error` : undefined}
        />
        <Checkbox name="overrideCoverage" label="Override coverage-below-minimum block (HRS:Override)" />
        <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">
          Approve
        </Button>
      </form>
      <form action={rejectFormAction} className="flex items-center gap-2">
        <label htmlFor={`reject-reason-${item.stepId}`} className="sr-only">
          Rejection reason
        </label>
        <Input
          id={`reject-reason-${item.stepId}`}
          name="reason"
          required
          placeholder="Rejection reason (required)"
          className="min-w-[10rem] flex-1 text-xs"
          invalid={Boolean(rejectState.error)}
          aria-describedby={rejectState.error ? `reject-${item.stepId}-error` : undefined}
        />
        <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
          Reject
        </Button>
      </form>
      {approveState.error ? <ValidationMessage id={`approve-${item.stepId}-error`}>{approveState.error}</ValidationMessage> : null}
      {rejectState.error ? <ValidationMessage id={`reject-${item.stepId}-error`}>{rejectState.error}</ValidationMessage> : null}
    </li>
  );
}

function AdjustBalanceForm({ adjustLeaveBalanceAction }: { adjustLeaveBalanceAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(adjustLeaveBalanceAction, INITIAL_STATE);
  const describedBy = state.error ? "adjust-balance-error" : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Manual balance adjustment (HRS:Override)</h2>
      <FormField id="adjust-employee-id" label="Employee (master record id)">
        <Input id="adjust-employee-id" name="employeeId" required placeholder="employee UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="adjust-leave-type-id" label="Leave type id">
        <Input id="adjust-leave-type-id" name="leaveTypeId" required placeholder="leave type UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="adjust-units" label="Units (positive to credit, negative to debit)">
        <Input id="adjust-units" type="number" step="any" name="units" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="adjust-effective-date" label="Effective date">
        <Input id="adjust-effective-date" type="date" name="effectiveDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="sm:col-span-2">
        <FormField id="adjust-reason" label="Reason">
          <Textarea id="adjust-reason" name="reason" required minLength={1} rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="sm:col-span-2">
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adjusting…">
          Post adjustment
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id="adjust-balance-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function SyncLifecycleForm({ syncLeaveLifecycleAction }: { syncLeaveLifecycleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(syncLeaveLifecycleAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Sync employee leave status</h2>
      <p className="text-xs text-neutral-500">Reconciles app.employees.lifecycle_status (active ↔ on_leave) against currently-in-effect approved leave -- run after a batch of approvals, or on a schedule.</p>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Syncing…">
        Sync now
      </Button>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CancelConflictingScheduleForm({ cancelConflictingScheduleAction }: { cancelConflictingScheduleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(cancelConflictingScheduleAction, INITIAL_STATE);
  const describedBy = state.error ? "cancel-conflicting-schedule-error" : undefined;
  return (
    <form action={formAction} className="grid grid-cols-1 gap-2 rounded-md border border-neutral-200 p-4 sm:grid-cols-2" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900 sm:col-span-2">Override a scheduled shift for approved leave (HRS:Override)</h2>
      <p className="text-xs text-neutral-500 sm:col-span-2">An approved leave never silently cancels an already-published shift -- use this to do so explicitly, per shift-day.</p>
      <FormField id="ccs-leave-request-id" label="Leave request id">
        <Input id="ccs-leave-request-id" name="leaveRequestId" required placeholder="leave request UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="ccs-work-date" label="Work date">
        <Input id="ccs-work-date" type="date" name="workDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="ccs-expected-version" label="Schedule assignment's current version">
        <Input id="ccs-expected-version" type="number" name="expectedVersion" required min="1" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="ccs-reason" label="Reason (optional)">
        <Input id="ccs-reason" name="reason" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div className="sm:col-span-2">
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Cancelling…">
          Cancel conflicting shift
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id="cancel-conflicting-schedule-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

export function LeaveAdminPanel({
  requests,
  inbox,
  decideLeaveRequestAction,
  adjustLeaveBalanceAction,
  syncLeaveLifecycleAction,
  cancelConflictingScheduleAction,
}: {
  requests: LeaveRequestListRow[];
  inbox: LeaveApprovalInboxItem[];
  decideLeaveRequestAction: (requestStepId: string, decision: "approved" | "rejected") => BoundAction;
  adjustLeaveBalanceAction: BoundAction;
  syncLeaveLifecycleAction: BoundAction;
  cancelConflictingScheduleAction: BoundAction;
}) {
  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Leave, permit and business trip</h1>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Pending your decision</h2>
        {inbox.length === 0 ? (
          <EmptyState title="Nothing pending your decision" description="Requests routed to you for approval appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {inbox.map((item) => (
              <InboxItemRow key={item.stepId} item={item} decideAction={decideLeaveRequestAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Requests</h2>
        {requests.length === 0 ? (
          <EmptyState title="No leave requests yet" description="Employee requests appear here once submitted." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="p-2">Employee</th>
                  <th className="p-2">Type</th>
                  <th className="p-2">Dates</th>
                  <th className="p-2">Units</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Payroll input</th>
                </tr>
              </thead>
              <tbody>
                {requests.map((r) => (
                  <tr key={r.id} className="border-t border-neutral-100">
                    <td className="p-2">{r.employeeName}</td>
                    <td className="p-2">{r.leaveTypeCode.replace(/_/g, " ")}</td>
                    <td className="p-2 text-xs">
                      {r.dateFrom}
                      {r.dateTo !== r.dateFrom ? ` – ${r.dateTo}` : ""}
                    </td>
                    <td className="p-2">{r.totalUnits}</td>
                    <td className="p-2">
                      <StatusBadge tone={REQUEST_STATUS_TONE[r.status] ?? "neutral"} label={r.status.replace(/_/g, " ")} />
                    </td>
                    <td className="p-2">
                      <StatusBadge tone={r.payrollInputStatus === "approved" ? "success" : "neutral"} label={r.payrollInputStatus} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <AdjustBalanceForm adjustLeaveBalanceAction={adjustLeaveBalanceAction} />
      <SyncLifecycleForm syncLeaveLifecycleAction={syncLeaveLifecycleAction} />
      <CancelConflictingScheduleForm cancelConflictingScheduleAction={cancelConflictingScheduleAction} />
    </div>
  );
}
