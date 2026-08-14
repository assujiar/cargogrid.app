"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
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

function DecideOvertimeRequestForm({
  row,
  decideOvertimeRequestAction,
}: {
  row: OvertimeRequestAdminRow;
  decideOvertimeRequestAction: (requestId: string, expectedVersion: number, decision: Decision) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [approveState, approveFormAction, approvePending] = useActionState(decideOvertimeRequestAction(row.id, row.recordVersion, "approve"), INITIAL_STATE);
  const [rejectState, rejectFormAction, rejectPending] = useActionState(decideOvertimeRequestAction(row.id, row.recordVersion, "reject"), INITIAL_STATE);

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
        <label className="flex-1 text-xs text-neutral-500">
          Decision reason
          <textarea name="decidedReason" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" rows={1} />
        </label>
        <label className="text-xs text-neutral-500">
          Override approved minutes (optional)
          <input name="approvedMinutesOverride" type="number" min={0} className="mt-1 w-32 rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <div className="flex gap-2">
          <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">
            Approve
          </Button>
          <Button type="submit" formAction={rejectFormAction} variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </div>
      </form>
      {approveState.error ? <p role="alert" className="text-xs text-danger">{approveState.error}</p> : null}
      {rejectState.error ? <p role="alert" className="text-xs text-danger">{rejectState.error}</p> : null}
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
        <label className="flex-1 text-xs text-neutral-500">
          Decision reason
          <textarea name="decidedReason" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" rows={1} />
        </label>
        <div className="flex gap-2">
          <Button type="submit" variant="primary" loading={approvePending} loadingLabel="Approving…">
            Approve
          </Button>
          <Button type="submit" formAction={rejectFormAction} variant="destructive" loading={rejectPending} loadingLabel="Rejecting…">
            Reject
          </Button>
        </div>
      </form>
      {approveState.error ? <p role="alert" className="text-xs text-danger">{approveState.error}</p> : null}
      {rejectState.error ? <p role="alert" className="text-xs text-danger">{rejectState.error}</p> : null}
    </li>
  );
}

function CreatePeriodForm({ createTimesheetPeriodAction }: { createTimesheetPeriodAction: (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState> }) {
  const [state, formAction, pending] = useActionState(createTimesheetPeriodAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4 sm:flex-row sm:items-end">
      <label className="text-xs text-neutral-500">
        Code
        <input name="code" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="P-2026-08" />
      </label>
      <label className="text-xs text-neutral-500">
        Period start
        <input name="periodStart" type="date" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Period end
        <input name="periodEnd" type="date" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        Create period
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function PeriodRow({
  period,
  lockTimesheetPeriodAction,
  reopenTimesheetPeriodAction,
  generatePayrollTimeInputsForPeriodAction,
}: {
  period: TimesheetPeriodRow;
  lockTimesheetPeriodAction: (periodId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  reopenTimesheetPeriodAction: (periodId: string, expectedVersion: number) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  generatePayrollTimeInputsForPeriodAction: (periodId: string) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
}) {
  const [lockState, lockFormAction, lockPending] = useActionState(lockTimesheetPeriodAction(period.id, period.recordVersion), INITIAL_STATE);
  const [reopenState, reopenFormAction, reopenPending] = useActionState(reopenTimesheetPeriodAction(period.id, period.recordVersion), INITIAL_STATE);
  const [genState, genFormAction, genPending] = useActionState(generatePayrollTimeInputsForPeriodAction(period.id), INITIAL_STATE);

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
            <input name="reason" required placeholder="Reopen reason" className="rounded border border-neutral-300 p-2 text-xs" />
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
      {lockState.error ? <p role="alert" className="text-xs text-danger">{lockState.error}</p> : null}
      {reopenState.error ? <p role="alert" className="text-xs text-danger">{reopenState.error}</p> : null}
      {genState.error ? <p role="alert" className="text-xs text-danger">{genState.error}</p> : null}
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
          <label className="flex-1 text-xs text-neutral-500">
            Reason
            <input name="reason" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
          </label>
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
          <input name="reason" required placeholder="Reopen reason" className="rounded border border-neutral-300 p-2 text-xs" />
          <Button type="submit" variant="secondary" loading={reopenPending} loadingLabel="Reopening…">
            Reopen (HRS:Override)
          </Button>
        </form>
      ) : null}
      {approveState.error ? <p role="alert" className="text-xs text-danger">{approveState.error}</p> : null}
      {rejectState.error ? <p role="alert" className="text-xs text-danger">{rejectState.error}</p> : null}
      {reopenState.error ? <p role="alert" className="text-xs text-danger">{reopenState.error}</p> : null}
    </li>
  );
}

export function OvertimeTimesheetAdminPanel({
  overtimeRequests,
  timesheetEntries,
  periods,
  summaries,
  decideOvertimeRequestAction,
  decideTimesheetEntryAction,
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
  periods: TimesheetPeriodRow[];
  summaries: TimesheetPeriodSummaryRow[];
  decideOvertimeRequestAction: (requestId: string, expectedVersion: number, decision: Decision) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
  decideTimesheetEntryAction: (entryId: string, expectedVersion: number, decision: Decision) => (prevState: OvertimeTimesheetAdminActionState, formData: FormData) => Promise<OvertimeTimesheetAdminActionState>;
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
