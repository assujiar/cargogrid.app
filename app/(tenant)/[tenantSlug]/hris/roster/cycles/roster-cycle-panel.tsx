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
import type { RosterCycleDetail, ShiftTemplateRow } from "../../../../../../server/contracts/shift-roster/shift-roster.ts";
import type { RosterCycleActionState } from "./actions.ts";

type BoundAction = (prevState: RosterCycleActionState, formData: FormData) => Promise<RosterCycleActionState>;

const INITIAL_STATE: RosterCycleActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };

function CreateCycleForm({ createRosterCycleAction }: { createRosterCycleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createRosterCycleAction, INITIAL_STATE);
  const describedBy = state.error ? "create-cycle-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="cycle-name" label="Name">
        <Input id="cycle-name" name="name" required placeholder="e.g. 4-on 2-off" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="cycle-length" label="Cycle length (days)">
        <Input id="cycle-length" type="number" name="cycleLengthDays" min="1" max="60" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="cycle-org-unit" label="Org unit id (optional)">
        <Input id="cycle-org-unit" name="orgUnitId" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        Create roster cycle
      </Button>
      {state.error ? <ValidationMessage id="create-cycle-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function SlotForm({ dayOffset, shiftTemplates, setSlotAction }: { dayOffset: number; shiftTemplates: ShiftTemplateRow[]; setSlotAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(setSlotAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex items-center gap-2">
      <span className="w-16 text-xs text-neutral-500">Day {dayOffset}</span>
      <input type="hidden" name="dayOffset" value={dayOffset} />
      <label htmlFor={`slot-shift-${dayOffset}`} className="sr-only">
        Shift template, day {dayOffset}
      </label>
      <Select id={`slot-shift-${dayOffset}`} name="shiftTemplateId" className="text-sm" invalid={Boolean(state.error)} aria-describedby={state.error ? `slot-${dayOffset}-error` : undefined}>
        <option value="">— day off —</option>
        {shiftTemplates.map((t) => (
          <option key={t.id} value={t.id}>
            {t.code}
          </option>
        ))}
      </Select>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…">
        Save
      </Button>
      {state.error ? <ValidationMessage id={`slot-${dayOffset}-error`}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

function GenerateForm({ generateAction }: { generateAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(generateAction, INITIAL_STATE);
  const describedBy = state.error ? "generate-schedule-error" : undefined;
  return (
    <form action={formAction} className="mt-2 flex flex-wrap items-end gap-2 rounded-md bg-neutral-50 p-3" noValidate>
      <FormField id="generate-employee-ids" label="Employee ids (comma or space separated)">
        <Textarea id="generate-employee-ids" name="employeeIds" required rows={2} className="w-64" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="generate-from-date" label="From">
        <Input id="generate-from-date" type="date" name="fromDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="generate-to-date" label="To">
        <Input id="generate-to-date" type="date" name="toDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Generating…">
        Generate schedule assignments
      </Button>
      {state.error ? <ValidationMessage id="generate-schedule-error">{state.error}</ValidationMessage> : null}
      {state.info ? <p className="text-xs text-success">{state.info}</p> : null}
    </form>
  );
}

export function RosterCyclePanel({
  cycles,
  shiftTemplates,
  createRosterCycleAction,
  setRosterCycleSlotAction,
  publishRosterCycleAction,
  generateRosterScheduleAssignmentsAction,
}: {
  cycles: RosterCycleDetail[];
  shiftTemplates: ShiftTemplateRow[];
  createRosterCycleAction: BoundAction;
  setRosterCycleSlotAction: (rosterCycleId: string) => BoundAction;
  publishRosterCycleAction: (rosterCycleId: string, expectedVersion: number) => BoundAction;
  generateRosterScheduleAssignmentsAction: (rosterCycleId: string) => BoundAction;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);
  const [publishState, publishAction, publishPending] = useActionState(
    async (prev: RosterCycleActionState, formData: FormData) => {
      const cycleId = String(formData.get("rosterCycleId"));
      const expectedVersion = Number(formData.get("expectedVersion"));
      return publishRosterCycleAction(cycleId, expectedVersion)(prev, formData);
    },
    INITIAL_STATE,
  );

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Rotating roster cycles</h1>
      <CreateCycleForm createRosterCycleAction={createRosterCycleAction} />

      {cycles.length === 0 ? (
        <EmptyState title="No roster cycles yet" description="Create one above, then fill in every day-offset's shift (or day off) before publishing." />
      ) : (
        <ul className="flex flex-col gap-2">
          {cycles.map((c) => (
            <li key={c.id} className="rounded-md border border-neutral-200 p-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">
                  {c.name} ({c.cycleLengthDays}-day cycle)
                </span>
                <StatusBadge tone={STATUS_TONE[c.status] ?? "neutral"} label={c.status} />
              </div>
              <p className="text-xs text-neutral-500">{c.slots.length} of {c.cycleLengthDays} day-offsets filled</p>
              <Button type="button" variant="secondary" onClick={() => setExpanded(expanded === c.id ? null : c.id)} className="mt-2">
                {expanded === c.id ? "Collapse" : "Edit slots"}
              </Button>

              {expanded === c.id ? (
                <div className="mt-2 flex flex-col gap-2">
                  {c.status === "draft" ? (
                    <>
                      <div className="flex flex-col gap-1">
                        {Array.from({ length: c.cycleLengthDays }).map((_, offset) => (
                          <SlotForm key={offset} dayOffset={offset} shiftTemplates={shiftTemplates} setSlotAction={setRosterCycleSlotAction(c.id)} />
                        ))}
                      </div>
                      <form action={publishAction}>
                        <input type="hidden" name="rosterCycleId" value={c.id} />
                        <input type="hidden" name="expectedVersion" value={c.recordVersion} />
                        <Button type="submit" variant="primary" loading={publishPending} loadingLabel="Publishing…" disabled={c.slots.length !== c.cycleLengthDays}>
                          Publish cycle
                        </Button>
                      </form>
                      {publishState.error ? <ValidationMessage>{publishState.error}</ValidationMessage> : null}
                    </>
                  ) : (
                    <GenerateForm generateAction={generateRosterScheduleAssignmentsAction(c.id)} />
                  )}
                </div>
              ) : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
