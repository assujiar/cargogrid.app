"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type {
  OvertimeRequestAdminRow,
  TimesheetEntryAdminRow,
  TimesheetPeriodRow,
  TimesheetPeriodSummaryRow,
  Decision,
} from "../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";
import type { OvertimeTimesheetAdminActionState } from "./actions.ts";

const INITIAL_STATE: OvertimeTimesheetAdminActionState = { error: null };

const REQUEST_STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", pending_approval: "warning", approved: "success", rejected: "danger", cancelled: "neutral" };
const PERIOD_STATUS_TONE: Record<string, StatusTone> = { open: "info", locked: "success" };
const SUMMARY_STATUS_TONE: Record<string, StatusTone> = { pending: "neutral", submitted: "warning", approved: "success", rejected: "danger" };
const RECONCILIATION_TONE: Record<string, StatusTone> = { not_reconciled: "warning", matched: "success", mismatch: "danger", no_attendance: "neutral" };

/** The minimum an employee picker needs; `masterRecordId` is what every HRIS RPC calls `p_employee_id`. */
export interface EmployeeOption {
  readonly masterRecordId: string;
  readonly employeeNumber: string;
  readonly fullName: string;
}

function DecideOvertimeRequestForm({
  row,
  decideOvertimeRequestAction,
}: {
  row: OvertimeRequestAdminRow;
  decideOvertimeRequestAction: (requestId: string, expectedVersion: number, decision: Decision) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [approveState, approveFormAction, approvePending] = useActionState(decideOvertimeRequestAction(row.id, row.recordVersion, "approve"), INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(decideOvertimeRequestAction(row.id, row.recordVersion, "reject"), INITIAL_STATE);
  const reactId = useId();
  const approveErrorId = `${reactId}-approve-error`;
  const rejectErrorId = `${reactId}-reject-error`;
  const describedByIds = [approveState.error ? approveErrorId : null, rejectState.error ? rejectErrorId : null].filter(Boolean).join(" ") || undefined;

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {row.employeeFullName} ({row.employeeNumber}) — {row.workDate} — {row.requestType.replace(/_/g, " ")}
        </span>
        <StatusBadge tone={REQUEST_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      <div className="text-xs text-neutral-500">
        requested {row.requestedMinutes}m · reconciliation {row.reconciliationStatus.replace(/_/g, " ")}
        {row.eligibleMinutes !== null ? ` · eligible ${row.eligibleMinutes}m (${row.eligibleClassification ?? "-"})` : ""}
      </div>
      <form action={approveFormAction} className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <div className="flex-1">
          <FormField id={`${reactId}-decidedReason`} label="Decision reason">
            <Textarea id={`${reactId}-decidedReason`} name="decidedReason" required minLength={1} rows={1} invalid={Boolean(approveState.error || rejectState.error)} aria-describedby={describedByIds} />
          </FormField>
        </div>
        <FormField id={`${reactId}-approvedMinutesOverride`} label="Override approved minutes (optional)">
          <Input id={`${reactId}-approvedMinutesOverride`} name="approvedMinutesOverride" type="number" min={0} className="w-32" invalid={Boolean(approveState.error || rejectState.error)} aria-describedby={describedByIds} />
        </FormField>
        <div className="flex gap-2">
          <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">
            Approve
          </Button>
          <Button type="submit" formAction={rejectFormAction} variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </div>
      </form>
      {approveState.error ? <ValidationMessage id={approveErrorId}>{approveState.error}</ValidationMessage> : null}
      {rejectState.error ? <ValidationMessage id={rejectErrorId}>{rejectState.error}</ValidationMessage> : null}
    </li>
  );
}

function DecideTimesheetEntryForm({
  row,
  decideTimesheetEntryAction,
}: {
  row: TimesheetEntryAdminRow;
  decideTimesheetEntryAction: (entryId: string, expectedVersion: number, decision: Decision) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [approveState, approveFormAction, approvePending] = useActionState(decideTimesheetEntryAction(row.id, row.recordVersion, "approve"), INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(decideTimesheetEntryAction(row.id, row.recordVersion, "reject"), INITIAL_STATE);
  const reactId = useId();
  const approveErrorId = `${reactId}-approve-error`;
  const rejectErrorId = `${reactId}-reject-error`;
  const describedByIds = [approveState.error ? approveErrorId : null, rejectState.error ? rejectErrorId : null].filter(Boolean).join(" ") || undefined;

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {row.employeeFullName} ({row.employeeNumber}) — {row.workDate} — {row.entryMinutes}m{row.jobNumber ? ` — ${row.jobNumber}` : ""}
        </span>
        <StatusBadge tone={REQUEST_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      <div className="text-xs text-neutral-500">reconciliation {row.reconciliationStatus.replace(/_/g, " ")}</div>
      <form action={approveFormAction} className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <div className="flex-1">
          <FormField id={`${reactId}-decidedReason`} label="Decision reason">
            <Textarea id={`${reactId}-decidedReason`} name="decidedReason" required minLength={1} rows={1} invalid={Boolean(approveState.error || rejectState.error)} aria-describedby={describedByIds} />
          </FormField>
        </div>
        <div className="flex gap-2">
          <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">
            Approve
          </Button>
          <Button type="submit" formAction={rejectFormAction} variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </div>
      </form>
      {approveState.error ? <ValidationMessage id={approveErrorId}>{approveState.error}</ValidationMessage> : null}
      {rejectState.error ? <ValidationMessage id={rejectErrorId}>{rejectState.error}</ValidationMessage> : null}
    </li>
  );
}

/**
 * `ISS-2026-076`: the four forms below are the missing UI half of levers that already existed
 * server-side. Before them, HR's only move against an employee's own row was approve or reject —
 * a typo in someone's timesheet had to be bounced back and re-entered by that person, and an
 * overtime request could not be filed for someone who could not file it themselves.
 *
 * Every one of them is gated in the database (`HRS:Edit`, or `HRS:Approve` for payroll input).
 * Nothing here re-checks that, and nothing here hides a control to simulate a permission: a
 * viewer who submits gets the RPC's own refusal, rendered as an error, which is the truthful
 * outcome rather than a guess made in the browser.
 */
function EmployeePicker({ employees, required = true }: { employees: readonly EmployeeOption[]; required?: boolean }) {
  const reactId = useId();
  return (
    <div className="flex-1">
      <FormField id={reactId} label="Employee">
        <Select id={reactId} name="employeeId" required={required} defaultValue="">
          <option value="" disabled>
            Choose an employee…
          </option>
          {employees.map((e) => (
            <option key={e.masterRecordId} value={e.masterRecordId}>
              {e.fullName} ({e.employeeNumber})
            </option>
          ))}
        </Select>
      </FormField>
    </div>
  );
}

function CreateOvertimeRequestForEmployeeForm({
  employees,
  createOvertimeRequestForEmployeeAction,
}: {
  employees: readonly EmployeeOption[];
  createOvertimeRequestForEmployeeAction: (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [state, formAction, pending] = useActionState(createOvertimeRequestForEmployeeAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <EmployeePicker employees={employees} />
        <FormField id={`${reactId}-requestType`} label="Type">
          <Select id={`${reactId}-requestType`} name="requestType" defaultValue="planned" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="planned">planned</option>
            <option value="emergency_after_the_fact">emergency (after the fact)</option>
          </Select>
        </FormField>
        <FormField id={`${reactId}-unpaidBreakMinutes`} label="Unpaid break (min)">
          <Input id={`${reactId}-unpaidBreakMinutes`} name="unpaidBreakMinutes" type="number" min={0} step={1} className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <div className="flex-1">
          <FormField id={`${reactId}-requestedStartAt`} label="Start">
            <Input id={`${reactId}-requestedStartAt`} name="requestedStartAt" type="datetime-local" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <div className="flex-1">
          <FormField id={`${reactId}-requestedEndAt`} label="End">
            <Input id={`${reactId}-requestedEndAt`} name="requestedEndAt" type="datetime-local" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>
      <FormField id={`${reactId}-reason`} label="Reason (recorded against the employee's record)">
        <Textarea id={`${reactId}-reason`} name="reason" required minLength={1} rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Filing…">
          File on behalf of employee
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CreateTimesheetEntryForEmployeeForm({
  employees,
  createTimesheetEntryForEmployeeAction,
}: {
  employees: readonly EmployeeOption[];
  createTimesheetEntryForEmployeeAction: (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [state, formAction, pending] = useActionState(createTimesheetEntryForEmployeeAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <EmployeePicker employees={employees} />
        <FormField id={`${reactId}-workDate`} label="Work date">
          <Input id={`${reactId}-workDate`} name="workDate" type="date" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-entryMinutes`} label="Worked (min)">
          <Input id={`${reactId}-entryMinutes`} name="entryMinutes" type="number" min={1} step={1} required className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-unpaidBreakMinutes`} label="Unpaid break (min)">
          <Input id={`${reactId}-unpaidBreakMinutes`} name="unpaidBreakMinutes" type="number" min={0} step={1} className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id={`${reactId}-notes`} label="Notes (optional)">
        <Input id={`${reactId}-notes`} name="notes" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">
          Record on behalf of employee
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CorrectDraftEntryForm({
  row,
  updateTimesheetEntryDraftAction,
}: {
  row: TimesheetEntryAdminRow;
  updateTimesheetEntryDraftAction: (entryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [state, formAction, pending] = useActionState(updateTimesheetEntryDraftAction(row.id, row.recordVersion), INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {row.employeeFullName} ({row.employeeNumber}) — {row.workDate}
        </span>
        <StatusBadge tone={REQUEST_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      {/*
        The note is pre-filled, not left blank. `update_timesheet_entry_draft` writes `p_notes`
        unconditionally, so a blank field would erase a note the person correcting the row was
        never shown -- which is why ISS-2026-315 added `notes` to the listing in the same change.
      */}
      <form action={formAction} className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <FormField id={`${reactId}-entryMinutes`} label="Worked (min)">
          <Input id={`${reactId}-entryMinutes`} name="entryMinutes" type="number" min={1} step={1} required defaultValue={row.entryMinutes} className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id={`${reactId}-unpaidBreakMinutes`} label="Unpaid break (min)">
          <Input id={`${reactId}-unpaidBreakMinutes`} name="unpaidBreakMinutes" type="number" min={0} step={1} defaultValue={row.unpaidBreakMinutes} className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <div className="flex-1">
          <FormField id={`${reactId}-notes`} label="Notes">
            <Input id={`${reactId}-notes`} name="notes" defaultValue={row.notes ?? ""} invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
          Correct draft
        </Button>
      </form>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </li>
  );
}

function ReconcileOvertimeRequestRow({
  row,
  reconcileOvertimeRequestActualAction,
}: {
  row: OvertimeRequestAdminRow;
  reconcileOvertimeRequestActualAction: (requestId: string) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [state, formAction, pending] = useActionState(reconcileOvertimeRequestActualAction(row.id), INITIAL_STATE);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {row.employeeFullName} ({row.employeeNumber}) — {row.workDate} — approved {row.approvedMinutes ?? row.requestedMinutes}m
        </span>
        <StatusBadge tone={RECONCILIATION_TONE[row.reconciliationStatus] ?? "neutral"} label={row.reconciliationStatus.replace(/_/g, " ")} />
      </div>
      <form action={formAction}>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reconciling…">
          Reconcile against attendance
        </Button>
      </form>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </li>
  );
}

function CreatePeriodForm({ createTimesheetPeriodAction }: { createTimesheetPeriodAction: (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState> }) {
  const [state, formAction, pending] = useActionState(createTimesheetPeriodAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4 sm:flex-row sm:items-end">
      <FormField id={`${reactId}-code`} label="Code">
        <Input id={`${reactId}-code`} name="code" required placeholder="P-2026-08" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-periodStart`} label="Period start">
        <Input id={`${reactId}-periodStart`} name="periodStart" type="date" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-periodEnd`} label="Period end">
        <Input id={`${reactId}-periodEnd`} name="periodEnd" type="date" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        Create period
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function PeriodRow({
  period,
  employees,
  lockTimesheetPeriodAction,
  reopenTimesheetPeriodAction,
  generatePayrollTimeInputsForPeriodAction,
  generatePayrollTimeInputAction,
}: {
  period: TimesheetPeriodRow;
  employees: readonly EmployeeOption[];
  lockTimesheetPeriodAction: (periodId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  reopenTimesheetPeriodAction: (periodId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  generatePayrollTimeInputsForPeriodAction: (periodId: string) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  generatePayrollTimeInputAction: (periodId: string) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [lockState, lockFormAction, lockPending] = useActionState(lockTimesheetPeriodAction(period.id, period.recordVersion), INITIAL_STATE);
  const [reopenState, reopenFormAction, reopenPending] = useActionState(reopenTimesheetPeriodAction(period.id, period.recordVersion), INITIAL_STATE);
  const [genState, genFormAction, genPending] = useActionState(generatePayrollTimeInputsForPeriodAction(period.id), INITIAL_STATE);
  const [oneState, oneFormAction, onePending] = useActionState(generatePayrollTimeInputAction(period.id), INITIAL_STATE);
  const reopenReasonId = `reopen-period-reason-${period.id}`;
  const reopenErrorId = `reopen-period-error-${period.id}`;

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {period.code} — {period.periodStart} to {period.periodEnd}
        </span>
        <StatusBadge tone={PERIOD_STATUS_TONE[period.status] ?? "neutral"} label={period.status} />
      </div>
      <div className="flex flex-wrap items-center gap-2">
        {period.status === "open" ? (
          <form action={lockFormAction}>
            <Button type="submit" variant="secondary" loading={lockPending} loadingLabel="Locking…">
              Lock period
            </Button>
          </form>
        ) : (
          <form action={reopenFormAction} className="flex items-center gap-2">
            <label className="sr-only" htmlFor={reopenReasonId}>
              Reopen reason
            </label>
            <Input id={reopenReasonId} name="reason" required placeholder="Reopen reason" className="text-xs" invalid={Boolean(reopenState.error)} aria-describedby={reopenState.error ? reopenErrorId : undefined} />
            <Button type="submit" variant="secondary" loading={reopenPending} loadingLabel="Reopening…">
              Reopen (HRS:Override)
            </Button>
          </form>
        )}
        {period.status === "locked" ? (
          <form action={genFormAction}>
            <Button type="submit" variant="primary" loading={genPending} loadingLabel="Generating…">
              Generate payroll inputs
            </Button>
          </form>
        ) : null}
      </div>
      {/*
        ISS-2026-076: the singular, per-employee generate. The bulk button above regenerates the
        whole period; when one person's figures are corrected after the fact, redoing everyone's
        is a far larger action than the situation calls for, and one nobody wants to explain.
      */}
      {period.status === "locked" && employees.length > 0 ? (
        <form action={oneFormAction} className="flex flex-col gap-2 sm:flex-row sm:items-end">
          <EmployeePicker employees={employees} />
          <Button type="submit" variant="secondary" loading={onePending} loadingLabel="Generating…">
            Regenerate for one employee
          </Button>
        </form>
      ) : null}
      {lockState.error ? <ValidationMessage>{lockState.error}</ValidationMessage> : null}
      {reopenState.error ? <ValidationMessage id={reopenErrorId}>{reopenState.error}</ValidationMessage> : null}
      {genState.error ? <ValidationMessage>{genState.error}</ValidationMessage> : null}
      {oneState.error ? <ValidationMessage>{oneState.error}</ValidationMessage> : null}
    </li>
  );
}

function SummaryRow({
  summary,
  approveTimesheetPeriodSummaryAction,
  rejectTimesheetPeriodSummaryAction,
  reopenTimesheetPeriodSummaryAction,
}: {
  summary: TimesheetPeriodSummaryRow;
  approveTimesheetPeriodSummaryAction: (summaryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  rejectTimesheetPeriodSummaryAction: (summaryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  reopenTimesheetPeriodSummaryAction: (summaryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [approveState, approveFormAction, approvePending] = useActionState(approveTimesheetPeriodSummaryAction(summary.id, summary.recordVersion), INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(rejectTimesheetPeriodSummaryAction(summary.id, summary.recordVersion), INITIAL_STATE);
  const [reopenState, reopenFormAction, reopenPending] = useActionState(reopenTimesheetPeriodSummaryAction(summary.id, summary.recordVersion), INITIAL_STATE);
  const reactId = useId();
  const approveErrorId = `${reactId}-approve-error`;
  const rejectErrorId = `${reactId}-reject-error`;
  const reopenErrorId = `${reactId}-reopen-error`;
  const decisionDescribedBy = [approveState.error ? approveErrorId : null, rejectState.error ? rejectErrorId : null].filter(Boolean).join(" ") || undefined;

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {summary.employeeFullName} ({summary.employeeNumber})
        </span>
        <StatusBadge tone={SUMMARY_STATUS_TONE[summary.status] ?? "neutral"} label={summary.status} />
      </div>
      <div className="text-xs text-neutral-500">
        regular {summary.totalRegularMinutes}m · OT weekday {summary.totalOvertimeWeekdayMinutes}m · weekend {summary.totalOvertimeWeekendMinutes}m · holiday {summary.totalOvertimeHolidayMinutes}m
      </div>
      {summary.status === "submitted" ? (
        <form action={approveFormAction} className="flex flex-col gap-2 sm:flex-row sm:items-end">
          <div className="flex-1">
            <FormField id={`${reactId}-reason`} label="Reason">
              <Input id={`${reactId}-reason`} name="reason" required invalid={Boolean(approveState.error || rejectState.error)} aria-describedby={decisionDescribedBy} />
            </FormField>
          </div>
          <div className="flex gap-2">
            <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">
              Approve
            </Button>
            <Button type="submit" formAction={rejectFormAction} variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
              Reject
            </Button>
          </div>
        </form>
      ) : null}
      {summary.status === "approved" ? (
        <form action={reopenFormAction} className="flex items-center gap-2">
          <label className="sr-only" htmlFor={`${reactId}-reopen-reason`}>
            Reopen reason
          </label>
          <Input id={`${reactId}-reopen-reason`} name="reason" required placeholder="Reopen reason" className="text-xs" invalid={Boolean(reopenState.error)} aria-describedby={reopenState.error ? reopenErrorId : undefined} />
          <Button type="submit" variant="secondary" loading={reopenPending} loadingLabel="Reopening…">
            Reopen (HRS:Override)
          </Button>
        </form>
      ) : null}
      {approveState.error ? <ValidationMessage id={approveErrorId}>{approveState.error}</ValidationMessage> : null}
      {rejectState.error ? <ValidationMessage id={rejectErrorId}>{rejectState.error}</ValidationMessage> : null}
      {reopenState.error ? <ValidationMessage id={reopenErrorId}>{reopenState.error}</ValidationMessage> : null}
    </li>
  );
}

export function OvertimeTimesheetAdminPanel({
  overtimeRequests,
  timesheetEntries,
  draftEntries,
  reconcilableRequests,
  employees,
  periods,
  summaries,
  decideOvertimeRequestAction,
  decideTimesheetEntryAction,
  createOvertimeRequestForEmployeeAction,
  createTimesheetEntryForEmployeeAction,
  updateTimesheetEntryDraftAction,
  reconcileOvertimeRequestActualAction,
  generatePayrollTimeInputAction,
  createTimesheetPeriodAction,
  lockTimesheetPeriodAction,
  reopenTimesheetPeriodAction,
  approveTimesheetPeriodSummaryAction,
  rejectTimesheetPeriodSummaryAction,
  reopenTimesheetPeriodSummaryAction,
  generatePayrollTimeInputsForPeriodAction,
}: {
  overtimeRequests: OvertimeRequestAdminRow[];
  timesheetEntries: TimesheetEntryAdminRow[];
  /** Draft (not yet submitted) entries HR may correct in place -- ISS-2026-076. */
  draftEntries: TimesheetEntryAdminRow[];
  /** Approved overtime not yet reconciled against attendance -- ISS-2026-076. */
  reconcilableRequests: OvertimeRequestAdminRow[];
  employees: readonly EmployeeOption[];
  periods: TimesheetPeriodRow[];
  summaries: TimesheetPeriodSummaryRow[];
  decideOvertimeRequestAction: (requestId: string, expectedVersion: number, decision: Decision) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  decideTimesheetEntryAction: (entryId: string, expectedVersion: number, decision: Decision) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  createOvertimeRequestForEmployeeAction: (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  createTimesheetEntryForEmployeeAction: (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  updateTimesheetEntryDraftAction: (entryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  reconcileOvertimeRequestActualAction: (requestId: string) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  generatePayrollTimeInputAction: (periodId: string) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  createTimesheetPeriodAction: (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  lockTimesheetPeriodAction: (periodId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  reopenTimesheetPeriodAction: (periodId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  approveTimesheetPeriodSummaryAction: (summaryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  rejectTimesheetPeriodSummaryAction: (summaryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  reopenTimesheetPeriodSummaryAction: (summaryId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  generatePayrollTimeInputsForPeriodAction: (periodId: string) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  return (
    <div className="mx-auto flex max-w-4xl flex-col gap-8">
      <h1 className="text-xl font-semibold text-neutral-900">Overtime and timesheet workspace</h1>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Pending overtime requests</h2>
        {overtimeRequests.length === 0 ? (
          <EmptyState title="No pending overtime requests" description="Requests awaiting decision will appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {overtimeRequests.map((r) => (
              <DecideOvertimeRequestForm key={r.id} row={r} decideOvertimeRequestAction={decideOvertimeRequestAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Pending timesheet entries</h2>
        {timesheetEntries.length === 0 ? (
          <EmptyState title="No pending timesheet entries" description="Entries awaiting decision will appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {timesheetEntries.map((e) => (
              <DecideTimesheetEntryForm key={e.id} row={e} decideTimesheetEntryAction={decideTimesheetEntryAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Record on behalf of an employee</h2>
        <p className="text-xs text-neutral-500">
          For people who cannot file for themselves — field crew without an account, someone on leave, a correction agreed
          verbally. The employee&apos;s own record shows who filed it.
        </p>
        {employees.length === 0 ? (
          <EmptyState title="No employees to file for" description="Employees you may act for will appear here once the roster has active records." />
        ) : (
          <>
            <CreateOvertimeRequestForEmployeeForm employees={employees} createOvertimeRequestForEmployeeAction={createOvertimeRequestForEmployeeAction} />
            <CreateTimesheetEntryForEmployeeForm employees={employees} createTimesheetEntryForEmployeeAction={createTimesheetEntryForEmployeeAction} />
          </>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Draft entries you can correct</h2>
        <p className="text-xs text-neutral-500">
          Fix a mistake in place rather than rejecting it and asking the employee to re-enter. Only drafts — once an entry is
          submitted, approve or reject it above.
        </p>
        {draftEntries.length === 0 ? (
          <EmptyState title="No draft entries" description="Entries still in draft will appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {draftEntries.map((e) => (
              <CorrectDraftEntryForm key={e.id} row={e} updateTimesheetEntryDraftAction={updateTimesheetEntryDraftAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Approved overtime awaiting attendance reconciliation</h2>
        {reconcilableRequests.length === 0 ? (
          <EmptyState title="Nothing awaiting reconciliation" description="Approved overtime that has not been matched against attendance will appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {reconcilableRequests.map((r) => (
              <ReconcileOvertimeRequestRow key={r.id} row={r} reconcileOvertimeRequestActualAction={reconcileOvertimeRequestActualAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Timesheet periods</h2>
        <CreatePeriodForm createTimesheetPeriodAction={createTimesheetPeriodAction} />
        {periods.length === 0 ? (
          <EmptyState title="No timesheet periods yet" description="Create a period above to begin the approval/lock workflow." />
        ) : (
          <ul className="flex flex-col gap-2">
            {periods.map((p) => (
              <PeriodRow
                key={p.id}
                period={p}
                lockTimesheetPeriodAction={lockTimesheetPeriodAction}
                reopenTimesheetPeriodAction={reopenTimesheetPeriodAction}
                generatePayrollTimeInputsForPeriodAction={generatePayrollTimeInputsForPeriodAction}
                generatePayrollTimeInputAction={generatePayrollTimeInputAction}
                employees={employees}
              />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Period summaries awaiting decision</h2>
        {summaries.length === 0 ? (
          <EmptyState title="No period summaries awaiting decision" description="Employee-submitted summaries will appear here." />
        ) : (
          <ul className="flex flex-col gap-2">
            {summaries.map((s) => (
              <SummaryRow
                key={s.id}
                summary={s}
                approveTimesheetPeriodSummaryAction={approveTimesheetPeriodSummaryAction}
                rejectTimesheetPeriodSummaryAction={rejectTimesheetPeriodSummaryAction}
                reopenTimesheetPeriodSummaryAction={reopenTimesheetPeriodSummaryAction}
              />
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
