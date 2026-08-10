"use client";

import { useActionState, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
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
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-4">
      <label className="text-xs text-neutral-500">
        Code
        <input name="code" required className="mt-1 rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. MORNING" />
      </label>
      <label className="text-xs text-neutral-500">
        Name
        <input name="name" required className="mt-1 rounded border border-neutral-300 p-2 text-sm" placeholder="e.g. Morning Fixed Shift" />
      </label>
      <label className="text-xs text-neutral-500">
        Org unit id (optional -- blank = tenant-wide)
        <input name="orgUnitId" className="mt-1 rounded border border-neutral-300 p-2 text-sm" placeholder="org_unit UUID" />
      </label>
      <Button type="submit" variant="primary" loading={pending} loadingLabel="Creating…">
        Create shift template
      </Button>
      {state.error ? <p role="alert" className="text-xs text-danger">{state.error}</p> : null}
    </form>
  );
}

function SegmentRow({ index }: { index: number }) {
  return (
    <div className="grid grid-cols-3 gap-2">
      <label className="text-xs text-neutral-500">
        Segment {index + 1} type
        <select name={`segmentType${index}`} defaultValue={index === 0 ? "work" : ""} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="">— skip —</option>
          <option value="work">Work</option>
          <option value="break">Break</option>
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Start
        <input type="time" name={`startTime${index}`} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        End
        <input type="time" name={`endTime${index}`} className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
    </div>
  );
}

function CreateVersionForm({ shiftTemplateId, createAndPublishVersionAction }: { shiftTemplateId: string; createAndPublishVersionAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createAndPublishVersionAction, INITIAL_STATE);
  const [segmentRowCount, setSegmentRowCount] = useState(1);

  return (
    <form action={formAction} className="mt-2 grid grid-cols-1 gap-2 rounded-md bg-neutral-50 p-3 sm:grid-cols-2">
      <label className="text-xs text-neutral-500">
        Timezone (IANA)
        <input name="timezone" required defaultValue="Asia/Jakarta" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Effective from
        <input type="date" name="effectiveFrom" required className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Shift type
        <select name="shiftType" defaultValue="fixed" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="fixed">Fixed</option>
          <option value="flexible">Flexible</option>
          <option value="split">Split</option>
        </select>
      </label>
      <label className="text-xs text-neutral-500">
        Day boundary (overnight cutover, optional)
        <input type="time" name="dayBoundaryLocalTime" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Grace override (late, minutes, optional)
        <input type="number" name="graceLateMinutes" min="0" max="240" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs text-neutral-500">
        Grace override (early leave, minutes, optional)
        <input type="number" name="graceEarlyMinutes" min="0" max="240" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>

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
      {state.error ? <p role="alert" className="text-xs text-danger sm:col-span-2">{state.error}</p> : null}
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
