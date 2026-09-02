"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type {
  ScheduleAssignmentListRow,
  ShiftTemplateRow,
  SwapRequestRow,
  RosterHolidayRow,
  CoveragePreviewRow,
} from "../../../../../server/contracts/shift-roster/shift-roster.ts";
import type { RosterAdminActionState } from "./actions.ts";

type BoundAction = (prevState: RosterAdminActionState, formData: FormData) => Promise<RosterAdminActionState>;

const INITIAL_STATE: RosterAdminActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { scheduled: "neutral", published: "success", cancelled: "danger", superseded: "neutral" };
const COVERAGE_TONE: Record<string, StatusTone> = { met: "success", below_minimum: "warning" };

function AssignForm({ shiftTemplates, assignEmployeeScheduleAction }: { shiftTemplates: ShiftTemplateRow[]; assignEmployeeScheduleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(assignEmployeeScheduleAction, INITIAL_STATE);
  const published = shiftTemplates.filter((t) => t.publishedVersionId);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4">
      <FormField id={`${reactId}-employeeId`} label="Employee id">
        <Input id={`${reactId}-employeeId`} name="employeeId" required placeholder="employee UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-shiftTemplateVersionId`} label="Shift version">
        <Select id={`${reactId}-shiftTemplateVersionId`} name="shiftTemplateVersionId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">— select —</option>
          {published.map((t) => (
            <option key={t.id} value={t.publishedVersionId ?? ""}>
              {t.code} (v{t.publishedVersionNumber})
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`${reactId}-workDate`} label="Work date">
        <Input id={`${reactId}-workDate`} type="date" name="workDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Assigning…">
        Assign schedule
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function PublishForm({ publishScheduleAssignmentsAction }: { publishScheduleAssignmentsAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(publishScheduleAssignmentsAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4">
      <FormField id={`${reactId}-fromDate`} label="From">
        <Input id={`${reactId}-fromDate`} type="date" name="fromDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-toDate`} label="To">
        <Input id={`${reactId}-toDate`} type="date" name="toDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Publishing…">
        Publish scheduled range
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function SwapDecisionForm({ requestId, expectedVersion, decision, decideSwapAction }: { requestId: string; expectedVersion: number; decision: "approve" | "reject"; decideSwapAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(decideSwapAction, INITIAL_STATE);
  const reactId = useId();
  const reasonId = `${reactId}-decidedReason`;
  const errorId = `${reactId}-error`;
  return (
    <form action={formAction} className="mt-1 flex flex-wrap items-end gap-2">
      <FormField id={reasonId} label="Reason">
        <Input id={reasonId} name="decidedReason" required invalid={Boolean(state.error)} aria-describedby={state.error ? errorId : undefined} />
      </FormField>
      <input type="hidden" name="requestId" value={requestId} />
      <input type="hidden" name="expectedVersion" value={expectedVersion} />
      <Button type="submit" variant={decision === "approve" ? "primary" : "destructive"} loading={pending} loadingLabel="Saving…">
        {decision === "approve" ? "Approve swap" : "Reject swap"}
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function HolidayForm({ setRosterHolidayAction }: { setRosterHolidayAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(setRosterHolidayAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4">
      <FormField id={`${reactId}-holidayDate`} label="Date">
        <Input id={`${reactId}-holidayDate`} type="date" name="holidayDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-name`} label="Name">
        <Input id={`${reactId}-name`} name="name" required placeholder="e.g. Independence Day" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-orgUnitId`} label="Org unit id (optional -- blank = tenant-wide)">
        <Input id={`${reactId}-orgUnitId`} name="orgUnitId" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Checkbox name="isWorkingDay" label="Treat as a working day (override)" />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Add holiday
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function CoverageRequirementForm({ shiftTemplates, setCoverageRequirementAction }: { shiftTemplates: ShiftTemplateRow[]; setCoverageRequirementAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(setCoverageRequirementAction, INITIAL_STATE);
  const reactId = useId();
  const errorId = `${reactId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4">
      <FormField id={`${reactId}-orgUnitId`} label="Org unit id">
        <Input id={`${reactId}-orgUnitId`} name="orgUnitId" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`${reactId}-shiftTemplateId`} label="Shift template">
        <Select id={`${reactId}-shiftTemplateId`} name="shiftTemplateId" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">— select —</option>
          {shiftTemplates.map((t) => (
            <option key={t.id} value={t.id}>
              {t.code}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`${reactId}-dayOfWeek`} label="Day of week">
        <Select id={`${reactId}-dayOfWeek`} name="dayOfWeek" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
          {["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"].map((d, i) => (
            <option key={d} value={i}>
              {d}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id={`${reactId}-minHeadcount`} label="Min headcount">
        <Input type="number" id={`${reactId}-minHeadcount`} name="minHeadcount" min="0" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Save requirement
      </Button>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function RosterAdminPanel({
  assignments,
  shiftTemplates,
  pendingSwaps,
  holidays,
  coveragePreview,
  assignEmployeeScheduleAction,
  publishScheduleAssignmentsAction,
  decideSwapAction,
  setRosterHolidayAction,
  setCoverageRequirementAction,
}: {
  assignments: ScheduleAssignmentListRow[];
  shiftTemplates: ShiftTemplateRow[];
  pendingSwaps: SwapRequestRow[];
  holidays: RosterHolidayRow[];
  coveragePreview: CoveragePreviewRow[];
  assignEmployeeScheduleAction: BoundAction;
  publishScheduleAssignmentsAction: BoundAction;
  decideSwapAction: (requestId: string, expectedVersion: number, decision: "approve" | "reject") => BoundAction;
  setRosterHolidayAction: BoundAction;
  setCoverageRequirementAction: BoundAction;
}) {
  return (
    <div className="flex flex-col gap-8">
      <h1 className="text-xl font-semibold text-neutral-900">Roster and scheduling</h1>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">Assign an employee to a shift</h2>
        <AssignForm shiftTemplates={shiftTemplates} assignEmployeeScheduleAction={assignEmployeeScheduleAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">Publish scheduled assignments</h2>
        <PublishForm publishScheduleAssignmentsAction={publishScheduleAssignmentsAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">Recent schedule assignments</h2>
        {assignments.length === 0 ? (
          <EmptyState title="No schedule assignments yet" description="Assign an employee to a published shift above." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-max text-left text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                  <th className="py-2 pr-4">Employee</th>
                  <th className="py-2 pr-4">Work date</th>
                  <th className="py-2 pr-4">Shift</th>
                  <th className="py-2 pr-4">Status</th>
                </tr>
              </thead>
              <tbody>
                {assignments.map((a) => (
                  <tr key={a.id} className="border-b border-neutral-100">
                    <td className="py-2 pr-4">
                      {a.employeeFullName} ({a.employeeNumber})
                    </td>
                    <td className="py-2 pr-4">{a.workDate}</td>
                    <td className="py-2 pr-4">{a.shiftTemplateName}</td>
                    <td className="py-2 pr-4">
                      <StatusBadge tone={STATUS_TONE[a.status] ?? "neutral"} label={a.status} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">Pending swap requests</h2>
        {pendingSwaps.length === 0 ? (
          <EmptyState title="No pending swap requests" />
        ) : (
          <ul className="flex flex-col gap-2">
            {pendingSwaps.map((s) => (
              <li key={s.id} className="rounded-md border border-neutral-200 p-3">
                <p className="text-sm">
                  {s.requestingEmployeeNumber} ⇄ {s.targetEmployeeNumber}
                </p>
                <div className="mt-1 flex flex-wrap gap-4">
                  <SwapDecisionForm requestId={s.id} expectedVersion={s.recordVersion} decision="approve" decideSwapAction={decideSwapAction(s.id, s.recordVersion, "approve")} />
                  <SwapDecisionForm requestId={s.id} expectedVersion={s.recordVersion} decision="reject" decideSwapAction={decideSwapAction(s.id, s.recordVersion, "reject")} />
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">Coverage preview (next 14 days, per org unit/shift requirement)</h2>
        {coveragePreview.length === 0 ? (
          <EmptyState title="No coverage requirements configured yet" description="Add one below to see a real met / below-minimum preview." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-max text-left text-sm">
              <thead>
                <tr className="border-b border-neutral-200 text-xs text-neutral-500">
                  <th className="py-2 pr-4">Date</th>
                  <th className="py-2 pr-4">Shift</th>
                  <th className="py-2 pr-4">Scheduled</th>
                  <th className="py-2 pr-4">Required</th>
                  <th className="py-2 pr-4">Status</th>
                </tr>
              </thead>
              <tbody>
                {coveragePreview.map((c, i) => (
                  <tr key={`${c.workDate}-${c.shiftTemplateId}-${i}`} className="border-b border-neutral-100">
                    <td className="py-2 pr-4">{c.workDate}</td>
                    <td className="py-2 pr-4">{c.shiftTemplateName}</td>
                    <td className="py-2 pr-4">{c.scheduledCount}</td>
                    <td className="py-2 pr-4">{c.minHeadcount}</td>
                    <td className="py-2 pr-4">
                      <StatusBadge tone={COVERAGE_TONE[c.coverageStatus] ?? "neutral"} label={c.coverageStatus} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <CoverageRequirementForm shiftTemplates={shiftTemplates} setCoverageRequirementAction={setCoverageRequirementAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-700">Holiday calendar</h2>
        {holidays.length === 0 ? (
          <EmptyState title="No holidays configured yet" />
        ) : (
          <ul className="flex flex-col gap-1 text-sm">
            {holidays.map((h) => (
              <li key={h.id}>
                {h.holidayDate} — {h.name} {h.isWorkingDay ? "(treated as a working day)" : ""}
              </li>
            ))}
          </ul>
        )}
        <HolidayForm setRosterHolidayAction={setRosterHolidayAction} />
      </section>
    </div>
  );
}
