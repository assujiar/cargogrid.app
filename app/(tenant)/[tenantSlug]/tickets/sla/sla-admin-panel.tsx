"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import type { TicketActionState } from "../actions.ts";
import { TICKET_CHANNELS, TICKET_PRIORITIES } from "../../../../../server/contracts/ticketing/ticketing.ts";
import type {
  SlaCalendarRow,
  SlaCalendarVersionRow,
  SlaPolicyRow,
  SlaPolicyVersionRow,
  TicketCategoryRow,
} from "../../../../../server/contracts/ticketing/ticketing.ts";

const INITIAL_STATE: TicketActionState = { error: null };

const VERSION_TONE: Record<string, StatusTone> = { draft: "neutral", published: "success", superseded: "neutral" };

type BoundAction = (prevState: TicketActionState, formData: FormData) => Promise<TicketActionState>;

function CreateCalendarForm({ createCalendarAction }: { createCalendarAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createCalendarAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Code
        <input name="code" required placeholder="STD" className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Name
        <input name="name" required placeholder="Standard Business Hours" className="min-w-[12rem] rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New calendar
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function CalendarCard({
  calendar,
  versions,
  createCalendarVersionAction,
  addBusinessHoursAction,
  addHolidayAction,
  publishCalendarVersionAction,
}: {
  calendar: SlaCalendarRow;
  versions: readonly SlaCalendarVersionRow[];
  createCalendarVersionAction: (calendarId: string) => BoundAction;
  addBusinessHoursAction: (calendarVersionId: string) => BoundAction;
  addHolidayAction: (calendarVersionId: string) => BoundAction;
  publishCalendarVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
}) {
  const [versionState, versionFormAction, versionPending] = useActionState(createCalendarVersionAction(calendar.id), INITIAL_STATE);
  const draftVersion = versions.find((v) => v.status === "draft") ?? null;

  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex items-center gap-2">
        <h3 className="text-sm font-semibold text-neutral-900">{calendar.name}</h3>
        <span className="font-mono text-xs text-neutral-500">{calendar.code}</span>
      </div>

      <ul className="flex flex-col gap-1 text-xs">
        {versions.length === 0 ? <li className="text-neutral-500">No versions yet.</li> : null}
        {versions.map((v) => (
          <li key={v.id} className="flex flex-wrap items-center gap-2">
            <StatusBadge tone={VERSION_TONE[v.status] ?? "neutral"} label={v.status} />
            <span>
              v{v.versionNumber} — {v.timezone}
              {v.is24x7 ? " (24x7)" : ""}
            </span>
            {v.status === "draft" ? <PublishCalendarVersionButton versionId={v.id} expectedVersion={v.recordVersion} publishCalendarVersionAction={publishCalendarVersionAction} /> : null}
          </li>
        ))}
      </ul>

      {draftVersion ? (
        <>
          <AddBusinessHoursForm calendarVersionId={draftVersion.id} addBusinessHoursAction={addBusinessHoursAction} />
          <AddHolidayForm calendarVersionId={draftVersion.id} addHolidayAction={addHolidayAction} />
        </>
      ) : (
        <form action={versionFormAction} className="flex flex-wrap items-end gap-2">
          <label className="flex flex-col gap-1 text-xs text-neutral-600">
            Timezone
            <input name="timezone" required placeholder="Asia/Jakarta" className="rounded border border-neutral-300 p-1.5 text-sm" />
          </label>
          <label className="flex items-center gap-1 text-xs text-neutral-600">
            <input type="checkbox" name="is24x7" /> 24x7
          </label>
          <Button type="submit" variant="secondary" loading={versionPending} loadingLabel="Creating…">
            New draft version
          </Button>
          {versionState.error ? (
            <p role="alert" className="w-full text-xs text-danger">
              {versionState.error}
            </p>
          ) : null}
        </form>
      )}
    </div>
  );
}

function AddBusinessHoursForm({ calendarVersionId, addBusinessHoursAction }: { calendarVersionId: string; addBusinessHoursAction: (calendarVersionId: string) => BoundAction }) {
  const [state, formAction, pending] = useActionState(addBusinessHoursAction(calendarVersionId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Day (0=Sun…6=Sat)
        <input name="dayOfWeek" type="number" min={0} max={6} required className="w-20 rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Start
        <input name="startTime" type="time" required className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        End
        <input name="endTime" type="time" required className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
        Add business hours
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function AddHolidayForm({ calendarVersionId, addHolidayAction }: { calendarVersionId: string; addHolidayAction: (calendarVersionId: string) => BoundAction }) {
  const [state, formAction, pending] = useActionState(addHolidayAction(calendarVersionId), INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Date
        <input name="holidayDate" type="date" required className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Name
        <input name="name" required placeholder="New Year" className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
        Add holiday
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function PublishCalendarVersionButton({ versionId, expectedVersion, publishCalendarVersionAction }: { versionId: string; expectedVersion: number; publishCalendarVersionAction: (versionId: string, expectedVersion: number) => BoundAction }) {
  const [state, formAction, pending] = useActionState(publishCalendarVersionAction(versionId, expectedVersion), INITIAL_STATE);
  return (
    <form action={formAction} className="inline">
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Publishing…">
        Publish
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function CreatePolicyForm({ createPolicyAction }: { createPolicyAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(createPolicyAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Code
        <input name="code" required placeholder="NARROW" className="rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <label className="flex flex-col gap-1 text-xs text-neutral-600">
        Name
        <input name="name" required placeholder="General Issue SLA" className="min-w-[12rem] rounded border border-neutral-300 p-1.5 text-sm" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New policy
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function PolicyCard({
  policy,
  versions,
  calendars,
  categories,
  createPolicyVersionAction,
  publishPolicyVersionAction,
}: {
  policy: SlaPolicyRow;
  versions: readonly SlaPolicyVersionRow[];
  calendars: readonly SlaCalendarRow[];
  categories: readonly TicketCategoryRow[];
  createPolicyVersionAction: (policyId: string) => BoundAction;
  publishPolicyVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
}) {
  const [state, formAction, pending] = useActionState(createPolicyVersionAction(policy.id), INITIAL_STATE);
  return (
    <div className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div className="flex items-center gap-2">
        <h3 className="text-sm font-semibold text-neutral-900">{policy.name}</h3>
        <span className="font-mono text-xs text-neutral-500">{policy.code}</span>
      </div>

      <ul className="flex flex-col gap-1 text-xs">
        {versions.length === 0 ? <li className="text-neutral-500">No versions yet.</li> : null}
        {versions.map((v) => (
          <li key={v.id} className="flex flex-wrap items-center gap-2">
            <StatusBadge tone={VERSION_TONE[v.status] ?? "neutral"} label={v.status} />
            <span>
              v{v.versionNumber} — {v.channel}
              {v.priority ? `/${v.priority}` : ""} — {v.responseTargetMinutes}m / {v.resolutionTargetMinutes}m (rank {v.precedenceRank})
            </span>
            {v.status === "draft" ? <PublishCalendarVersionButton versionId={v.id} expectedVersion={v.recordVersion} publishCalendarVersionAction={publishPolicyVersionAction} /> : null}
          </li>
        ))}
      </ul>

      <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
        <label className="flex flex-col gap-1 text-xs text-neutral-600">
          Channel
          <select name="channel" required className="rounded border border-neutral-300 p-1.5 text-sm">
            {TICKET_CHANNELS.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-neutral-600">
          Category (optional = any)
          <select name="categoryId" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
            <option value="">Any category</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-neutral-600">
          Priority (optional = any)
          <select name="priority" defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
            <option value="">Any priority</option>
            {TICKET_PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-neutral-600">
          Calendar
          <select name="calendarId" required defaultValue="" className="rounded border border-neutral-300 p-1.5 text-sm">
            <option value="" disabled>
              Select…
            </option>
            {calendars.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </select>
        </label>
        <label className="flex flex-col gap-1 text-xs text-neutral-600">
          Response target (min)
          <input name="responseTargetMinutes" type="number" min={1} required className="w-24 rounded border border-neutral-300 p-1.5 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-neutral-600">
          Resolution target (min)
          <input name="resolutionTargetMinutes" type="number" min={1} required className="w-24 rounded border border-neutral-300 p-1.5 text-sm" />
        </label>
        <label className="flex flex-col gap-1 text-xs text-neutral-600">
          Precedence rank
          <input name="precedenceRank" type="number" defaultValue={0} className="w-20 rounded border border-neutral-300 p-1.5 text-sm" />
        </label>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
          New draft version
        </Button>
        {state.error ? (
          <p role="alert" className="w-full text-xs text-danger">
            {state.error}
          </p>
        ) : null}
      </form>
    </div>
  );
}

export function SlaAdminPanel({
  calendars,
  calendarVersionsByCalendar,
  policies,
  policyVersionsByPolicy,
  categories,
  createCalendarAction,
  createCalendarVersionAction,
  addBusinessHoursAction,
  addHolidayAction,
  publishCalendarVersionAction,
  createPolicyAction,
  createPolicyVersionAction,
  publishPolicyVersionAction,
}: {
  calendars: readonly SlaCalendarRow[];
  calendarVersionsByCalendar: Record<string, readonly SlaCalendarVersionRow[]>;
  policies: readonly SlaPolicyRow[];
  policyVersionsByPolicy: Record<string, readonly SlaPolicyVersionRow[]>;
  categories: readonly TicketCategoryRow[];
  createCalendarAction: BoundAction;
  createCalendarVersionAction: (calendarId: string) => BoundAction;
  addBusinessHoursAction: (calendarVersionId: string) => BoundAction;
  addHolidayAction: (calendarVersionId: string) => BoundAction;
  publishCalendarVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
  createPolicyAction: BoundAction;
  createPolicyVersionAction: (policyId: string) => BoundAction;
  publishPolicyVersionAction: (versionId: string, expectedVersion: number) => BoundAction;
}) {
  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">Business calendars</h2>
        <CreateCalendarForm createCalendarAction={createCalendarAction} />
        <div className="flex flex-col gap-3">
          {calendars.map((c) => (
            <CalendarCard
              key={c.id}
              calendar={c}
              versions={calendarVersionsByCalendar[c.id] ?? []}
              createCalendarVersionAction={createCalendarVersionAction}
              addBusinessHoursAction={addBusinessHoursAction}
              addHolidayAction={addHolidayAction}
              publishCalendarVersionAction={publishCalendarVersionAction}
            />
          ))}
        </div>
      </section>

      <section className="flex flex-col gap-3">
        <h2 className="text-sm font-semibold text-neutral-900">SLA policies</h2>
        <CreatePolicyForm createPolicyAction={createPolicyAction} />
        <div className="flex flex-col gap-3">
          {policies.map((p) => (
            <PolicyCard
              key={p.id}
              policy={p}
              versions={policyVersionsByPolicy[p.id] ?? []}
              calendars={calendars}
              categories={categories}
              createPolicyVersionAction={createPolicyVersionAction}
              publishPolicyVersionAction={publishPolicyVersionAction}
            />
          ))}
        </div>
      </section>
    </div>
  );
}
