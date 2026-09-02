"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { DateInput } from "../../../../../components/forms/date-input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
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
  const describedBy = state.error ? "create-sla-calendar-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id="sla-calendar-code" label="Code">
        <Input id="sla-calendar-code" name="code" required placeholder="STD" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="sla-calendar-name" label="Name">
        <Input id="sla-calendar-name" name="name" required placeholder="Standard Business Hours" className="min-w-[12rem]" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New calendar
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="create-sla-calendar-error">{state.error}</ValidationMessage>
        </div>
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
  // One card per calendar on the same page -- every id in this card is calendar-scoped.
  const versionErrorId = `sla-calendar-version-${calendar.id}-error`;
  const versionDescribedBy = versionState.error ? versionErrorId : undefined;

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
          <FormField id={`sla-calendar-version-timezone-${calendar.id}`} label="Timezone">
            <Input
              id={`sla-calendar-version-timezone-${calendar.id}`}
              name="timezone"
              required
              placeholder="Asia/Jakarta"
              invalid={Boolean(versionState.error)}
              aria-describedby={versionDescribedBy}
            />
          </FormField>
          <Checkbox id={`sla-calendar-version-24x7-${calendar.id}`} name="is24x7" label="24x7" aria-describedby={versionDescribedBy} />
          <Button type="submit" variant="secondary" loading={versionPending} loadingLabel="Creating…">
            New draft version
          </Button>
          {versionState.error ? (
            <div className="w-full">
              <ValidationMessage id={versionErrorId}>{versionState.error}</ValidationMessage>
            </div>
          ) : null}
        </form>
      )}
    </div>
  );
}

function AddBusinessHoursForm({ calendarVersionId, addBusinessHoursAction }: { calendarVersionId: string; addBusinessHoursAction: (calendarVersionId: string) => BoundAction }) {
  const [state, formAction, pending] = useActionState(addBusinessHoursAction(calendarVersionId), INITIAL_STATE);
  const errorId = `sla-business-hours-${calendarVersionId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <FormField id={`sla-bh-day-${calendarVersionId}`} label="Day (0=Sun…6=Sat)">
        <NumberInput id={`sla-bh-day-${calendarVersionId}`} name="dayOfWeek" min={0} max={6} required className="w-20" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`sla-bh-start-${calendarVersionId}`} label="Start">
        <Input id={`sla-bh-start-${calendarVersionId}`} name="startTime" type="time" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`sla-bh-end-${calendarVersionId}`} label="End">
        <Input id={`sla-bh-end-${calendarVersionId}`} name="endTime" type="time" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
        Add business hours
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function AddHolidayForm({ calendarVersionId, addHolidayAction }: { calendarVersionId: string; addHolidayAction: (calendarVersionId: string) => BoundAction }) {
  const [state, formAction, pending] = useActionState(addHolidayAction(calendarVersionId), INITIAL_STATE);
  const errorId = `sla-holiday-${calendarVersionId}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded bg-neutral-50 p-2">
      <FormField id={`sla-holiday-date-${calendarVersionId}`} label="Date">
        <DateInput id={`sla-holiday-date-${calendarVersionId}`} name="holidayDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id={`sla-holiday-name-${calendarVersionId}`} label="Name">
        <Input id={`sla-holiday-name-${calendarVersionId}`} name="name" required placeholder="New Year" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
        Add holiday
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
        </div>
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
  const describedBy = state.error ? "create-sla-policy-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 rounded-md border border-neutral-200 p-3">
      <FormField id="sla-policy-code" label="Code">
        <Input id="sla-policy-code" name="code" required placeholder="NARROW" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="sla-policy-name" label="Name">
        <Input id="sla-policy-name" name="name" required placeholder="General Issue SLA" className="min-w-[12rem]" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
        New policy
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="create-sla-policy-error">{state.error}</ValidationMessage>
        </div>
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
  // One card per policy on the same page -- every id in this form is policy-scoped.
  const errorId = `sla-policy-version-${policy.id}-error`;
  const describedBy = state.error ? errorId : undefined;
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
        <FormField id={`sla-policy-version-channel-${policy.id}`} label="Channel">
          <Select id={`sla-policy-version-channel-${policy.id}`} name="channel" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
            {TICKET_CHANNELS.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`sla-policy-version-category-${policy.id}`} label="Category (optional = any)">
          <Select id={`sla-policy-version-category-${policy.id}`} name="categoryId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="">Any category</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`sla-policy-version-priority-${policy.id}`} label="Priority (optional = any)">
          <Select id={`sla-policy-version-priority-${policy.id}`} name="priority" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="">Any priority</option>
            {TICKET_PRIORITIES.map((p) => (
              <option key={p} value={p}>
                {p}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`sla-policy-version-calendar-${policy.id}`} label="Calendar">
          <Select id={`sla-policy-version-calendar-${policy.id}`} name="calendarId" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="" disabled>
              Select…
            </option>
            {calendars.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id={`sla-policy-version-response-${policy.id}`} label="Response target (min)">
          <NumberInput
            id={`sla-policy-version-response-${policy.id}`}
            name="responseTargetMinutes"
            min={1}
            required
            className="w-24"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id={`sla-policy-version-resolution-${policy.id}`} label="Resolution target (min)">
          <NumberInput
            id={`sla-policy-version-resolution-${policy.id}`}
            name="resolutionTargetMinutes"
            min={1}
            required
            className="w-24"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <FormField id={`sla-policy-version-precedence-${policy.id}`} label="Precedence rank">
          <NumberInput
            id={`sla-policy-version-precedence-${policy.id}`}
            name="precedenceRank"
            defaultValue={0}
            className="w-20"
            invalid={Boolean(state.error)}
            aria-describedby={describedBy}
          />
        </FormField>
        <Button type="submit" variant="secondary" loading={pending} loadingLabel="Creating…">
          New draft version
        </Button>
        {state.error ? (
          <div className="w-full">
            <ValidationMessage id={errorId}>{state.error}</ValidationMessage>
          </div>
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
