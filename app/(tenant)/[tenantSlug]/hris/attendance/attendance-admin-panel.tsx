"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { SessionListRow, AttendanceExceptionRow, CorrectionRequestRow } from "../../../../../server/contracts/attendance/attendance.ts";
import type { AttendanceAdminActionState } from "./actions.ts";

type BoundAction = (prevState: AttendanceAdminActionState, formData: FormData) => Promise<AttendanceAdminActionState>;

const INITIAL_STATE: AttendanceAdminActionState = { error: null };
const SESSION_STATUS_TONE: Record<string, StatusTone> = { open: "info", closed: "success" };
const EXCEPTION_SEVERITY_TONE: Record<string, StatusTone> = { low: "neutral", medium: "warning", high: "danger" };

function ManualEntryForm({ recordManualEntryAction }: { recordManualEntryAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recordManualEntryAction, INITIAL_STATE);
  const describedBy = state.error ? "manual-entry-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h2 className="text-sm font-semibold text-neutral-900">Manual attendance entry</h2>
      <p className="text-xs text-neutral-500">For a missed punch or offline event -- never subject to geofence checks (an HR-authenticated action, decision 4).</p>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id="manual-entry-employee-id" label="Employee (master record id)">
          <Input id="manual-entry-employee-id" name="employeeId" required placeholder="employee UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="manual-entry-event-type" label="Event">
          <Select id="manual-entry-event-type" name="eventType" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="clock_in">Clock in</option>
            <option value="clock_out">Clock out</option>
          </Select>
        </FormField>
        <div className="sm:col-span-2">
          <FormField id="manual-entry-event-at" label="Event time">
            <Input id="manual-entry-event-at" type="datetime-local" name="eventAt" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="sm:col-span-2">
          <FormField id="manual-entry-reason" label="Reason">
            <Textarea id="manual-entry-reason" name="reason" required minLength={1} rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">
        Record entry
      </Button>
      {state.error ? <ValidationMessage id="manual-entry-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function ExceptionRow({
  exception,
  acknowledgeExceptionAction,
  waiveExceptionAction,
}: {
  exception: AttendanceExceptionRow;
  acknowledgeExceptionAction: (exceptionId: string, expectedVersion: number) => BoundAction;
  waiveExceptionAction: (exceptionId: string, expectedVersion: number) => BoundAction;
}) {
  const [ackState, ackFormAction, ackPending] = useActionState(acknowledgeExceptionAction(exception.id, exception.recordVersion), INITIAL_STATE);
  const [waiveState, waiveFormAction, waivePending] = useActionState(waiveExceptionAction(exception.id, exception.recordVersion), INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <div className="flex items-center justify-between">
        <span className="text-sm">
          {exception.employeeNumber} — {exception.exceptionType.replace(/_/g, " ")} ({exception.workDate})
        </span>
        <StatusBadge tone={EXCEPTION_SEVERITY_TONE[exception.severity] ?? "neutral"} label={exception.severity} />
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <form action={ackFormAction}>
          <Button type="submit" variant="secondary" loading={ackPending} loadingLabel="Acknowledging…">
            Acknowledge
          </Button>
        </form>
        <form action={waiveFormAction} className="flex flex-1 items-center gap-2">
          <label htmlFor={`waive-reason-${exception.id}`} className="sr-only">
            Waive reason
          </label>
          <Input id={`waive-reason-${exception.id}`} name="waiveReason" required placeholder="Waive reason (required, HRS:Override)" className="min-w-[12rem] flex-1 text-xs" invalid={Boolean(waiveState.error)} aria-describedby={waiveState.error ? `waive-${exception.id}-error` : undefined} />
          <Button type="submit" variant="destructive" loading={waivePending} loadingLabel="Waiving…">
            Waive
          </Button>
        </form>
      </div>
      {ackState.error ? <ValidationMessage>{ackState.error}</ValidationMessage> : null}
      {waiveState.error ? <ValidationMessage id={`waive-${exception.id}-error`}>{waiveState.error}</ValidationMessage> : null}
    </li>
  );
}

function CorrectionRow({ correction, decideCorrectionAction }: { correction: CorrectionRequestRow; decideCorrectionAction: (requestId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction }) {
  const [approveState, approveFormAction, approvePending] = useActionState(decideCorrectionAction(correction.id, correction.recordVersion, "approve"), INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(decideCorrectionAction(correction.id, correction.recordVersion, "reject"), INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3">
      <span className="text-sm">
        {correction.employeeNumber ?? "—"} — {correction.requestType.replace(/_/g, " ")} ({correction.workDate})
        {correction.hasEvidence ? <StatusBadge tone="info" label="has evidence" /> : null}
      </span>
      <div className="flex flex-wrap gap-2">
        <form action={approveFormAction} className="flex flex-1 items-center gap-2">
          <label htmlFor={`approve-corr-reason-${correction.id}`} className="sr-only">
            Decision reason
          </label>
          <Input id={`approve-corr-reason-${correction.id}`} name="decidedReason" required placeholder="Decision reason (required)" className="min-w-[12rem] flex-1 text-xs" invalid={Boolean(approveState.error)} aria-describedby={approveState.error ? `approve-corr-${correction.id}-error` : undefined} />
          <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">
            Approve
          </Button>
        </form>
        <form action={rejectFormAction} className="flex flex-1 items-center gap-2">
          <label htmlFor={`reject-corr-reason-${correction.id}`} className="sr-only">
            Decision reason
          </label>
          <Input id={`reject-corr-reason-${correction.id}`} name="decidedReason" required placeholder="Decision reason (required)" className="min-w-[12rem] flex-1 text-xs" invalid={Boolean(rejectState.error)} aria-describedby={rejectState.error ? `reject-corr-${correction.id}-error` : undefined} />
          <Button type="submit" variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </form>
      </div>
      {approveState.error ? <ValidationMessage id={`approve-corr-${correction.id}-error`}>{approveState.error}</ValidationMessage> : null}
      {rejectState.error ? <ValidationMessage id={`reject-corr-${correction.id}-error`}>{rejectState.error}</ValidationMessage> : null}
    </li>
  );
}

function PayrollApprovalForm({ approvePayrollInputAction }: { approvePayrollInputAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(approvePayrollInputAction, INITIAL_STATE);
  const describedBy = state.error ? "payroll-approval-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="payroll-approval-from" label="From">
        <Input id="payroll-approval-from" type="date" name="fromDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="payroll-approval-to" label="To">
        <Input id="payroll-approval-to" type="date" name="toDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Approving…">
        Approve attendance for payroll input
      </Button>
      {state.error ? <ValidationMessage id="payroll-approval-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function RecalculateExceptionsForm({ recalculateExceptionsAction }: { recalculateExceptionsAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(recalculateExceptionsAction, INITIAL_STATE);
  const describedBy = state.error ? "recalc-exceptions-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="recalc-from" label="From">
        <Input id="recalc-from" type="date" name="fromDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="recalc-to" label="To (at most 92 days)">
        <Input id="recalc-to" type="date" name="toDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recalculating…">
        Recalculate exceptions for range
      </Button>
      {state.error ? <ValidationMessage id="recalc-exceptions-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function AttendanceAdminPanel({
  sessions,
  exceptions,
  corrections,
  recordManualEntryAction,
  decideCorrectionAction,
  acknowledgeExceptionAction,
  waiveExceptionAction,
  approvePayrollInputAction,
  recalculateExceptionsAction,
}: {
  sessions: SessionListRow[];
  exceptions: AttendanceExceptionRow[];
  corrections: CorrectionRequestRow[];
  recordManualEntryAction: BoundAction;
  decideCorrectionAction: (requestId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction;
  acknowledgeExceptionAction: (exceptionId: string, expectedVersion: number) => BoundAction;
  waiveExceptionAction: (exceptionId: string, expectedVersion: number) => BoundAction;
  approvePayrollInputAction: BoundAction;
  recalculateExceptionsAction: BoundAction;
}) {
  return (
    <div className="flex flex-col gap-6">
      <h1 className="text-xl font-semibold text-neutral-900">Attendance</h1>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Sessions</h2>
        {sessions.length === 0 ? (
          <EmptyState title="No attendance sessions yet" description="Sessions appear here once employees start clocking in." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="p-2">Employee</th>
                  <th className="p-2">Date</th>
                  <th className="p-2">Status</th>
                  <th className="p-2">Clock in</th>
                  <th className="p-2">Clock out</th>
                  <th className="p-2">Exceptions</th>
                  <th className="p-2">Payroll input</th>
                </tr>
              </thead>
              <tbody>
                {sessions.map((s) => (
                  <tr key={s.id} className="border-t border-neutral-100">
                    <td className="p-2">
                      {s.employeeFullName} <span className="text-xs text-neutral-500">({s.employeeNumber})</span>
                    </td>
                    <td className="p-2">{s.workDate}</td>
                    <td className="p-2">
                      <StatusBadge tone={SESSION_STATUS_TONE[s.status] ?? "neutral"} label={s.status} />
                    </td>
                    <td className="p-2 text-xs">{s.effectiveClockInAt ? new Date(s.effectiveClockInAt).toLocaleTimeString() : "—"}</td>
                    <td className="p-2 text-xs">{s.effectiveClockOutAt ? new Date(s.effectiveClockOutAt).toLocaleTimeString() : "—"}</td>
                    <td className="p-2">{s.openExceptionCount > 0 ? <StatusBadge tone="warning" label={String(s.openExceptionCount)} /> : "—"}</td>
                    <td className="p-2">
                      <StatusBadge tone={s.payrollInputStatus === "approved" ? "success" : "neutral"} label={s.payrollInputStatus} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Open exceptions</h2>
        {exceptions.length === 0 ? (
          <EmptyState title="No open exceptions" description="Late arrivals, early leaves, missing clock-outs, and geofence violations appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {exceptions.map((x) => (
              <ExceptionRow key={x.id} exception={x} acknowledgeExceptionAction={acknowledgeExceptionAction} waiveExceptionAction={waiveExceptionAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Pending correction requests</h2>
        {corrections.length === 0 ? (
          <EmptyState title="No pending correction requests" description="Employee- and HR-submitted corrections needing a decision appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {corrections.map((c) => (
              <CorrectionRow key={c.id} correction={c} decideCorrectionAction={decideCorrectionAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Payroll input approval</h2>
        <PayrollApprovalForm approvePayrollInputAction={approvePayrollInputAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Recalculate exceptions</h2>
        <p className="text-xs text-neutral-500">Re-run exception detection over a date range after a policy correction (decision 7 -- bounded, synchronous, at most 92 days).</p>
        <RecalculateExceptionsForm recalculateExceptionsAction={recalculateExceptionsAction} />
      </section>

      <ManualEntryForm recordManualEntryAction={recordManualEntryAction} />
    </div>
  );
}
