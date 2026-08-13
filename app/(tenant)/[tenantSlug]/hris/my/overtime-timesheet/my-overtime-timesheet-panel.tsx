"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type {
  OvertimeRequestRow,
  TimesheetEntryRow,
  TimesheetPeriodRow,
  TimesheetPeriodSummaryRow,
  RequestType,
} from "../../../../../../server/contracts/overtime-timesheet/overtime-timesheet.ts";
import type { MyOvertimeTimesheetActionState } from "./actions.ts";

const INITIAL_STATE: MyOvertimeTimesheetActionState = { error: null };
const REQUEST_STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", pending_approval: "warning", approved: "success", rejected: "danger", cancelled: "neutral" };
const SUMMARY_STATUS_TONE: Record<string, StatusTone> = { pending: "neutral", submitted: "warning", approved: "success", rejected: "danger" };

type BoundAction = (prevState: MyOvertimeTimesheetActionState, formData: FormData) => Promise<MyOvertimeTimesheetActionState>;

function CreateOvertimeRequestForm({ createOvertimeRequestAction }: { createOvertimeRequestAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createOvertimeRequestAction, INITIAL_STATE);
  const [requestType, setRequestType] = useState<RequestType>("planned");

  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Request overtime</h3>
      <label className="text-xs text-neutral-500">
        Type
        <select name="requestType" value={requestType} onChange={(e) => setRequestType(e.target.value as RequestType)} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="planned">Planned (before the work happens)</option>
          <option value="emergency_after_the_fact">Emergency (after the work happened)</option>
        </select>
      </label>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          Start
          <input type="datetime-local" name="requestedStartAt" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          End
          <input type="datetime-local" name="requestedEndAt" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
      </div>
      <label className="text-xs text-neutral-500">
        Unpaid break (minutes)
        <input type="number" name="unpaidBreakMinutes" min={0} defaultValue={0} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Reason
        <textarea name="reason" required minLength={1} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" rows={2} />
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Requesting…">
        Request overtime
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function OvertimeRequestRowItem({
  row,
  submitOvertimeRequestAction,
  cancelOvertimeRequestAction,
}: {
  row: OvertimeRequestRow;
  submitOvertimeRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
  cancelOvertimeRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
}) {
  const [submitState, submitFormAction, submitPending] = useActionState(submitOvertimeRequestAction(row.id, row.recordVersion), INITIAL_STATE);
  const [cancelState, cancelFormAction, cancelPending] = useActionState(cancelOvertimeRequestAction(row.id, row.recordVersion), INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {row.workDate} — {row.requestType.replace(/_/g, " ")} — {row.requestedMinutes}m
        </span>
        <StatusBadge tone={REQUEST_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      {row.eligibleMinutes !== null ? (
        <div className="text-xs text-neutral-500">
          eligible {row.eligibleMinutes}m ({row.eligibleClassification ?? "-"}) · approved {row.approvedMinutes ?? "-"}m
        </div>
      ) : null}
      <div className="flex gap-2">
        {row.status === "draft" ? (
          <form action={submitFormAction}>
            <Button type="submit" variant="secondary" loading={submitPending} loadingLabel="Submitting…">
              Submit
            </Button>
          </form>
        ) : null}
        {row.status === "draft" || row.status === "pending_approval" || row.status === "approved" ? (
          <form action={cancelFormAction} className="flex items-center gap-2">
            <input name="reason" required placeholder="Cancel reason" className="rounded border border-neutral-300 p-2 text-xs" />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">
              Cancel
            </Button>
          </form>
        ) : null}
      </div>
      {submitState.error ? <p role="alert" className="text-xs text-danger">{submitState.error}</p> : null}
      {cancelState.error ? <p role="alert" className="text-xs text-danger">{cancelState.error}</p> : null}
    </li>
  );
}

function CreateTimesheetEntryForm({ createTimesheetEntryAction }: { createTimesheetEntryAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createTimesheetEntryAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h3 className="text-sm font-semibold text-neutral-900">Log a timesheet entry</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <label className="text-xs text-neutral-500">
          Work date
          <input type="date" name="workDate" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Minutes worked
          <input type="number" name="entryMinutes" min={1} max={1440} required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Unpaid break (minutes)
          <input type="number" name="unpaidBreakMinutes" min={0} defaultValue={0} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
        </label>
        <label className="text-xs text-neutral-500">
          Job order id (optional)
          <input name="jobOrderId" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="job_order UUID" />
        </label>
        <label className="text-xs text-neutral-500 sm:col-span-2">
          Shipment order id (optional -- multi-job allocation: log a SEPARATE entry per job/shipment for the same day)
          <input name="shipmentOrderId" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" placeholder="shipment_order UUID" />
        </label>
      </div>
      <label className="text-xs text-neutral-500">
        Notes (optional)
        <textarea name="notes" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" rows={2} />
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Logging…">
        Log entry
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function TimesheetEntryRowItem({
  row,
  submitTimesheetEntryAction,
  cancelTimesheetEntryAction,
}: {
  row: TimesheetEntryRow;
  submitTimesheetEntryAction: (entryId: string, expectedVersion: number) => BoundAction;
  cancelTimesheetEntryAction: (entryId: string, expectedVersion: number) => BoundAction;
}) {
  const [submitState, submitFormAction, submitPending] = useActionState(submitTimesheetEntryAction(row.id, row.recordVersion), INITIAL_STATE);
  const [cancelState, cancelFormAction, cancelPending] = useActionState(cancelTimesheetEntryAction(row.id, row.recordVersion), INITIAL_STATE);

  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-3 text-sm">
      <div className="flex items-center justify-between">
        <span>
          {row.workDate} — {row.entryMinutes}m{row.jobNumber ? ` — ${row.jobNumber}` : ""}
        </span>
        <StatusBadge tone={REQUEST_STATUS_TONE[row.status] ?? "neutral"} label={row.status.replace(/_/g, " ")} />
      </div>
      {row.eligibleMinutes !== null ? <div className="text-xs text-neutral-500">eligible {row.eligibleMinutes}m · approved {row.approvedMinutes ?? "-"}m</div> : null}
      <div className="flex gap-2">
        {row.status === "draft" ? (
          <form action={submitFormAction}>
            <Button type="submit" variant="secondary" loading={submitPending} loadingLabel="Submitting…">
              Submit
            </Button>
          </form>
        ) : null}
        {row.status === "draft" || row.status === "pending_approval" || row.status === "approved" ? (
          <form action={cancelFormAction} className="flex items-center gap-2">
            <input name="reason" required placeholder="Cancel reason" className="rounded border border-neutral-300 p-2 text-xs" />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">
              Cancel
            </Button>
          </form>
        ) : null}
      </div>
      {submitState.error ? <p role="alert" className="text-xs text-danger">{submitState.error}</p> : null}
      {cancelState.error ? <p role="alert" className="text-xs text-danger">{cancelState.error}</p> : null}
    </li>
  );
}

function SubmitPeriodSummaryForm({ periods, myEmployeeId, submitTimesheetPeriodSummaryAction }: { periods: TimesheetPeriodRow[]; myEmployeeId: string | null; submitTimesheetPeriodSummaryAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(submitTimesheetPeriodSummaryAction, INITIAL_STATE);
  const openPeriods = periods.filter((p) => p.status === "open");

  if (!myEmployeeId) {
    return <p className="text-xs text-neutral-500">Your employee profile could not be resolved -- period summary submission is unavailable.</p>;
  }
  if (openPeriods.length === 0) {
    return <p className="text-xs text-neutral-500">No open period is available to submit against right now.</p>;
  }

  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4 sm:flex-row sm:items-end">
      <input type="hidden" name="employeeId" value={myEmployeeId} />
      <label className="flex-1 text-xs text-neutral-500">
        Period
        <select name="periodId" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          {openPeriods.map((p) => (
            <option key={p.id} value={p.id}>
              {p.code} ({p.periodStart} to {p.periodEnd})
            </option>
          ))}
        </select>
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">
        Submit my period summary
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

export function MyOvertimeTimesheetPanel({
  overtimeRequests,
  timesheetEntries,
  periods,
  summaries,
  myEmployeeId,
  createOvertimeRequestAction,
  submitOvertimeRequestAction,
  cancelOvertimeRequestAction,
  createTimesheetEntryAction,
  submitTimesheetEntryAction,
  cancelTimesheetEntryAction,
  submitTimesheetPeriodSummaryAction,
}: {
  overtimeRequests: OvertimeRequestRow[];
  timesheetEntries: TimesheetEntryRow[];
  periods: TimesheetPeriodRow[];
  summaries: TimesheetPeriodSummaryRow[];
  myEmployeeId: string | null;
  createOvertimeRequestAction: BoundAction;
  submitOvertimeRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
  cancelOvertimeRequestAction: (requestId: string, expectedVersion: number) => BoundAction;
  createTimesheetEntryAction: BoundAction;
  submitTimesheetEntryAction: (entryId: string, expectedVersion: number) => BoundAction;
  cancelTimesheetEntryAction: (entryId: string, expectedVersion: number) => BoundAction;
  submitTimesheetPeriodSummaryAction: BoundAction;
}) {
  return (
    <div className="mx-auto flex max-w-2xl flex-col gap-8">
      <h1 className="text-xl font-semibold text-neutral-900">My overtime and timesheet</h1>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Overtime requests</h2>
        <CreateOvertimeRequestForm createOvertimeRequestAction={createOvertimeRequestAction} />
        {overtimeRequests.length === 0 ? (
          <EmptyState title="No overtime requests yet" description="Requests you submit will appear here with their review status." />
        ) : (
          <ul className="flex flex-col gap-2">
            {overtimeRequests.map((r) => (
              <OvertimeRequestRowItem key={r.id} row={r} submitOvertimeRequestAction={submitOvertimeRequestAction} cancelOvertimeRequestAction={cancelOvertimeRequestAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Timesheet entries</h2>
        <CreateTimesheetEntryForm createTimesheetEntryAction={createTimesheetEntryAction} />
        {timesheetEntries.length === 0 ? (
          <EmptyState title="No timesheet entries yet" description="Entries you log will appear here with their review status." />
        ) : (
          <ul className="flex flex-col gap-2">
            {timesheetEntries.map((e) => (
              <TimesheetEntryRowItem key={e.id} row={e} submitTimesheetEntryAction={submitTimesheetEntryAction} cancelTimesheetEntryAction={cancelTimesheetEntryAction} />
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">My period summaries</h2>
        <SubmitPeriodSummaryForm periods={periods} myEmployeeId={myEmployeeId} submitTimesheetPeriodSummaryAction={submitTimesheetPeriodSummaryAction} />
        {summaries.length === 0 ? (
          <EmptyState title="No period summaries yet" description="Submit your period above once your entries and overtime for that range are approved." />
        ) : (
          <ul className="flex flex-col gap-2">
            {summaries.map((s) => (
              <li key={s.id} className="flex items-center justify-between rounded-md border border-neutral-200 p-3 text-sm">
                <span>
                  regular {s.totalRegularMinutes}m · OT {s.totalOvertimeWeekdayMinutes + s.totalOvertimeWeekendMinutes + s.totalOvertimeHolidayMinutes}m
                </span>
                <StatusBadge tone={SUMMARY_STATUS_TONE[s.status] ?? "neutral"} label={s.status} />
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  );
}
