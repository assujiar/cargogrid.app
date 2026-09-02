"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { ShiftTemplateRow, ShiftType } from "../../../../../server/contracts/shift-roster/shift-roster.ts";
import type { ShiftTemplateActionState } from "./actions.ts";

type BoundAction = (prevState: ShiftTemplateActionState, formData: FormData) => Promise<ShiftTemplateActionState>;

const INITIAL_STATE: ShiftTemplateActionState = { error: null };
const STATUS_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", archived: "neutral" };
const MAX_SEGMENT_ROWS = 6;

function CreateTemplateForm({ createShiftTemplateAction }: { createShiftTemplateAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createShiftTemplateAction, INITIAL_STATE);
  const describedBy = state.error ? "create-shift-template-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4" noValidate>
      <FormField id="shift-template-code" label="Code">
        <Input id="shift-template-code" name="code" required placeholder="e.g. MORNING" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="shift-template-name" label="Name">
        <Input id="shift-template-name" name="name" required placeholder="e.g. Morning Fixed Shift" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="shift-template-org-unit" label="Org unit id (optional -- blank = tenant-wide)">
        <Input id="shift-template-org-unit" name="orgUnitId" placeholder="org_unit UUID" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        Create shift template
      </Button>
      {state.error ? <ValidationMessage id="create-shift-template-error">{state.error}</ValidationMessage> : null}
    </form>
  );
}

function SegmentRow({ index }: { index: number }) {
  return (
    <div className="grid grid-cols-3 gap-2">
      <FormField id={`segment-type-${index}`} label={`Segment ${index + 1} type`}>
        <Select id={`segment-type-${index}`} name={`segmentType${index}`} defaultValue={index === 0 ? "work" : ""}>
          <option value="">— skip —</option>
          <option value="work">Work</option>
          <option value="break">Break</option>
        </Select>
      </FormField>
      <FormField id={`segment-start-${index}`} label="Start">
        <Input id={`segment-start-${index}`} type="time" name={`startTime${index}`} />
      </FormField>
      <FormField id={`segment-end-${index}`} label="End">
        <Input id={`segment-end-${index}`} type="time" name={`endTime${index}`} />
      </FormField>
    </div>
  );
}

function CreateVersionForm({ shiftTemplateId, createAndPublishVersionAction }: { shiftTemplateId: string; createAndPublishVersionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishVersionAction, INITIAL_STATE);
  const [segmentRowCount, setSegmentRowCount] = useState(1);

  const describedBy = state.error ? `create-version-${shiftTemplateId}-error` : undefined;
  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2" noValidate>
      <FormField id={`sv-timezone-${shiftTemplateId}`} label="Timezone (IANA)">
        <Input id={`sv-timezone-${shiftTemplateId}`} name="timezone" required defaultValue="Asia/Jakarta" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`sv-effective-from-${shiftTemplateId}`} label="Effective from">
        <Input id={`sv-effective-from-${shiftTemplateId}`} type="date" name="effectiveFrom" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`sv-shift-type-${shiftTemplateId}`} label="Shift type">
        <Select id={`sv-shift-type-${shiftTemplateId}`} name="shiftType" defaultValue="fixed" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="fixed">Fixed</option>
          <option value="flexible">Flexible</option>
          <option value="split">Split</option>
        </Select>
      </FormField>
      <FormField id={`sv-day-boundary-${shiftTemplateId}`} label="Day boundary (overnight cutover, optional)">
        <Input id={`sv-day-boundary-${shiftTemplateId}`} type="time" name="dayBoundaryLocalTime" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`sv-grace-late-${shiftTemplateId}`} label="Grace override (late, minutes, optional)">
        <Input id={`sv-grace-late-${shiftTemplateId}`} type="number" name="graceLateMinutes" min="0" max="240" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`sv-grace-early-${shiftTemplateId}`} label="Grace override (early leave, minutes, optional)">
        <Input id={`sv-grace-early-${shiftTemplateId}`} type="number" name="graceEarlyMinutes" min="0" max="240" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>

      <div className="flex flex-col gap-2 sm:col-span-2">
        <span className="text-xs font-medium text-neutral-700">
          Segments (work/break, in chronological order -- only the LAST segment may cross midnight, e.g. 22:00 -&gt; 02:00)
        </span>
        {Array.from({ length: segmentRowCount }).map((_, i) => (
          <SegmentRow key={i} index={i} />
        ))}
        {segmentRowCount < MAX_SEGMENT_ROWS ? (
          <Button type="button" variant="secondary" onClick={() => setSegmentRowCount((n) => Math.min(n + 1, MAX_SEGMENT_ROWS))}>
            + Add segment
          </Button>
        ) : null}
      </div>

      <input type="hidden" name="shiftTemplateId" value={shiftTemplateId} />
      <div className="sm:col-span-2">
        <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating and publishing…">
          Create and publish version
        </Button>
      </div>
      {state.error ? (
        <div className="sm:col-span-2">
          <ValidationMessage id={`create-version-${shiftTemplateId}-error`}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

export function ShiftTemplatePanel({
  templates,
  createShiftTemplateAction,
  createAndPublishVersionAction,
}: {
  templates: ShiftTemplateRow[];
  createShiftTemplateAction: BoundAction;
  createAndPublishVersionAction: (shiftTemplateId: string) => BoundAction;
}) {
  const [expanded, setExpanded] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold text-neutral-900">Shift templates</h1>
      <CreateTemplateForm createShiftTemplateAction={createShiftTemplateAction} />

      {templates.length === 0 ? (
        <EmptyState title="No shift templates yet" description="Create one above -- no employee can be scheduled to a shift, and no roster cycle can be built, until at least one published shift template version exists." />
      ) : (
        <ul className="flex flex-col gap-2">
          {templates.map((t) => (
            <li key={t.id} className="rounded-md border border-neutral-200 p-3">
              <div className="flex items-center justify-between">
                <span className="text-sm font-medium">
                  {t.code} — {t.name}
                </span>
                <StatusBadge tone={STATUS_TONE[t.status] ?? "neutral"} label={t.status} />
              </div>
              <p className="text-xs text-neutral-500">
                {t.orgUnitId ? `Scoped to org unit ${t.orgUnitId}` : "Tenant-wide"} — published version: {t.publishedVersionNumber ?? "none yet"}
              </p>
              <Button type="button" variant="secondary" onClick={() => setExpanded(expanded === t.id ? null : t.id)} className="mt-2">
                {expanded === t.id ? "Cancel" : "Add version"}
              </Button>
              {expanded === t.id ? <CreateVersionForm shiftTemplateId={t.id} createAndPublishVersionAction={createAndPublishVersionAction(t.id)} /> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
