"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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

  const describedBy = state.error ? "create-overtime-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-neutral-900">Request overtime</h3>
      <FormField id="overtime-request-type" label="Type">
        <Select id="overtime-request-type" name="requestType" value={requestType} onChange={(e) => setRequestType(e.target.value as RequestType)} invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="planned">Planned (before the work happens)</option>
          <option value="emergency_after_the_fact">Emergency (after the work happened)</option>
        </Select>
      </FormField>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id="overtime-start" label="Start">
          <Input id="overtime-start" type="datetime-local" name="requestedStartAt" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="overtime-end" label="End">
          <Input id="overtime-end" type="datetime-local" name="requestedEndAt" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      <FormField id="overtime-unpaid-break" label="Unpaid break (minutes)">
        <Input id="overtime-unpaid-break" type="number" name="unpaidBreakMinutes" min={0} defaultValue={0} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="overtime-reason" label="Reason">
        <Textarea id="overtime-reason" name="reason" required minLength={1} rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Requesting…">
        Request overtime
      </Button>
      {state.error ? <ValidationMessage id="create-overtime-error">{state.error}</ValidationMessage> : null}
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
            <label htmlFor={`cancel-ot-reason-${row.id}`} className="sr-only">
              Cancel reason
            </label>
            <Input id={`cancel-ot-reason-${row.id}`} name="reason" required placeholder="Cancel reason" className="text-xs" invalid={Boolean(cancelState.error)} aria-describedby={cancelState.error ? `cancel-ot-${row.id}-error` : undefined} />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">
              Cancel
            </Button>
          </form>
        ) : null}
      </div>
      {submitState.error ? <ValidationMessage>{submitState.error}</ValidationMessage> : null}
      {cancelState.error ? <ValidationMessage id={`cancel-ot-${row.id}-error`}>{cancelState.error}</ValidationMessage> : null}
    </li>
  );
}

function CreateTimesheetEntryForm({ createTimesheetEntryAction }: { createTimesheetEntryAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createTimesheetEntryAction, INITIAL_STATE);
  const describedBy = state.error ? "create-timesheet-entry-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <h3 className="text-sm font-semibold text-neutral-900">Log a timesheet entry</h3>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        <FormField id="entry-work-date" label="Work date">
          <Input id="entry-work-date" type="date" name="workDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="entry-minutes" label="Minutes worked">
          <Input id="entry-minutes" type="number" name="entryMinutes" min={1} max={1440} required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="entry-unpaid-break" label="Unpaid break (minutes)">
          <Input id="entry-unpaid-break" type="number" name="unpaidBreakMinutes" min={0} defaultValue={0} invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="entry-job-order-id" label="Job order id (optional)">
          <Input id="entry-job-order-id" name="jobOrderId" placeholder="job_order UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <div className="sm:col-span-2">
          <FormField id="entry-shipment-order-id" label="Shipment order id (optional -- multi-job allocation: log a SEPARATE entry per job/shipment for the same day)">
            <Input id="entry-shipment-order-id" name="shipmentOrderId" placeholder="shipment_order UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>
      <FormField id="entry-notes" label="Notes (optional)">
        <Textarea id="entry-notes" name="notes" rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Logging…">
        Log entry
      </Button>
      {state.error ? <ValidationMessage id="create-timesheet-entry-error">{state.error}</ValidationMessage> : null}
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
            <label htmlFor={`cancel-ts-reason-${row.id}`} className="sr-only">
              Cancel reason
            </label>
            <Input id={`cancel-ts-reason-${row.id}`} name="reason" required placeholder="Cancel reason" className="text-xs" invalid={Boolean(cancelState.error)} aria-describedby={cancelState.error ? `cancel-ts-${row.id}-error` : undefined} />
            <Button type="submit" variant="destructive" loading={cancelPending} loadingLabel="Cancelling…">
              Cancel
            </Button>
          </form>
        ) : null}
      </div>
      {submitState.error ? <ValidationMessage>{submitState.error}</ValidationMessage> : null}
      {cancelState.error ? <ValidationMessage id={`cancel-ts-${row.id}-error`}>{cancelState.error}</ValidationMessage> : null}
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
    <form action={formAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4 sm:flex-row sm:items-end" noValidate>
      <input type="hidden" name="employeeId" value={myEmployeeId} />
      <div className="flex-1">
        <FormField id="period-summary-id" label="Period">
          <Select id="period-summary-id" name="periodId" required invalid={Boolean(state.error)} aria-describedby={state.error ? "submit-period-summary-error" : undefined}>
            {openPeriods.map((p) => (
              <option key={p.id} value={p.id}>
                {p.code} ({p.periodStart} to {p.periodEnd})
              </option>
            ))}
          </Select>
        </FormField>
      </div>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Submitting…">
        Submit my period summary
      </Button>
      {state.error ? <ValidationMessage id="submit-period-summary-error">{state.error}</ValidationMessage> : null}
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
