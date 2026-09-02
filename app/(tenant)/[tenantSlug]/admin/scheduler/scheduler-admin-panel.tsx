"use client";

/**
 * Presentational half of the automation console.
 *
 * The one idea a reader needs before the fields make sense: **a scheduled task runs as the person
 * who switched it on.** Not as a robot account, not as "the platform" — as a named, accountable
 * human whose authority is re-checked on every single run. So this panel makes three things
 * impossible to miss that a plainer table would bury:
 *
 *   1. Who each schedule currently runs as, and that switching it on transfers that to you.
 *   2. When a schedule has been auto-disabled because that person's authority went away — the
 *      failure mode that would otherwise look like "the sweep just stopped working".
 *   3. Which rows this particular admin may change at all, so the controls are disabled rather
 *      than letting a save fail against an authority rule the UI never showed.
 */

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../components/forms/number-input.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { TenantScheduledTask, ScheduledTaskRunStatus } from "../../../../../server/contracts/task-scheduler/task-scheduler.ts";
import { configureScheduledTaskAction, setScheduledTaskDelegationAction, SCHEDULER_INITIAL_STATE, type SchedulerFormState } from "./actions.ts";

const RUN_STATUS_TONE: Record<ScheduledTaskRunStatus, StatusTone> = {
  succeeded: "success",
  failed: "danger",
  unauthorized: "warning",
};

/**
 * Minutes are how the database stores an interval, and hours or days are how a person thinks
 * about one. Rendering 1440 to an administrator and asking them to reason about it is a small
 * unkindness that adds up across eleven rows.
 */
function humaniseInterval(minutes: number | null): string {
  if (minutes === null) return "—";
  if (minutes % 1440 === 0) {
    const days = minutes / 1440;
    return days === 1 ? "Once a day" : `Every ${days} days`;
  }
  if (minutes % 60 === 0) {
    const hours = minutes / 60;
    return hours === 1 ? "Once an hour" : `Every ${hours} hours`;
  }
  return `Every ${minutes} minutes`;
}

function formatInstant(value: string | null): string {
  return value ? value.replace("T", " ").slice(0, 16) : "—";
}

/**
 * ISS-2026-242: the shared field-error renderer -- `id` is what each control's `aria-describedby`
 * points at, and `ValidationMessage` also carries the `role="alert"` this hand-rolled paragraph
 * never had, so a save failure is announced rather than silently appearing.
 */
function ErrorBanner({ id, error }: { id?: string; error: string | null }) {
  if (!error) return null;
  return (
    <div className="mt-2">
      <ValidationMessage id={id}>{error}</ValidationMessage>
    </div>
  );
}

function SavedNote({ state }: { state: SchedulerFormState }) {
  if (!state.saved) return null;
  return <p className="mt-2 text-xs text-status-success-strong">Saved. This schedule now runs as you.</p>;
}

function ScheduleForm({ tenantSlug, task }: { tenantSlug: string; task: TenantScheduledTask }) {
  const boundAction = configureScheduledTaskAction.bind(null, tenantSlug);
  const [state, formAction, pending] = useActionState(boundAction, SCHEDULER_INITIAL_STATE);

  // ISS-2026-242: one ScheduleForm is rendered per task, so every id is scoped by taskCode; the
  // configure RPC returns one error for the whole save, so every control points at that one text.
  const intervalId = `sched-interval-${task.taskCode}`;
  const errorId = `sched-${task.taskCode}-error`;
  const describedBy = state.error ? errorId : undefined;

  return (
    <form action={formAction} className="mt-3 flex flex-wrap items-end gap-3">
      <input type="hidden" name="taskCode" value={task.taskCode} />
      <input type="hidden" name="requiredParams" value={task.requiredParams.join(",")} />

      <Checkbox
        id={`sched-enabled-${task.taskCode}`}
        name="enabled"
        label="Run automatically"
        defaultChecked={task.enabled}
        disabled={!task.configurableByActor}
        aria-describedby={describedBy}
      />

      <div className="w-32">
        <FormField id={intervalId} label="How often (minutes)" helpText={`No more often than every ${task.minIntervalMinutes} min`}>
          <NumberInput
            id={intervalId}
            name="intervalMinutes"
            min={task.minIntervalMinutes}
            step={1}
            defaultValue={task.intervalMinutes ?? task.defaultIntervalMinutes}
            disabled={!task.configurableByActor}
            invalid={Boolean(state.error)}
            aria-describedby={state.error ? `${intervalId}-help ${errorId}` : `${intervalId}-help`}
          />
        </FormField>
      </div>

      {task.requiredParams.map((key) => (
        <div key={key} className="w-64">
          <FormField id={`sched-param-${task.taskCode}-${key}`} label={key.replace(/_/g, " ")}>
            <Input
              id={`sched-param-${task.taskCode}-${key}`}
              type="text"
              name={`param_${key}`}
              defaultValue={String(task.params[key] ?? "")}
              disabled={!task.configurableByActor}
              invalid={Boolean(state.error)}
              aria-describedby={describedBy}
            />
          </FormField>
        </div>
      ))}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" disabled={!task.configurableByActor}>
        Save
      </Button>

      <ErrorBanner id={errorId} error={state.error} />
      <SavedNote state={state} />
    </form>
  );
}

/**
 * Supreme-Admin-only control. It is rendered to everyone rather than hidden, because hiding it
 * would leave a tenant admin unable to see WHY a task is not theirs to configure. The RPC is the
 * authority; this checkbox is disabled for anyone it would refuse.
 */
function DelegationForm({ tenantSlug, task, actorIsSupreme }: { tenantSlug: string; task: TenantScheduledTask; actorIsSupreme: boolean }) {
  const boundAction = setScheduledTaskDelegationAction.bind(null, tenantSlug);
  const [state, formAction, pending] = useActionState(boundAction, SCHEDULER_INITIAL_STATE);

  return (
    <form action={formAction} className="mt-2 flex flex-wrap items-center gap-2 text-xs">
      <input type="hidden" name="taskCode" value={task.taskCode} />
      <Checkbox
        id={`sched-delegation-${task.taskCode}`}
        name="tenantAdminConfigurable"
        label="Organisation admins may configure this"
        defaultChecked={task.tenantAdminConfigurable}
        disabled={!actorIsSupreme}
        aria-describedby={state.error ? `sched-delegation-${task.taskCode}-error` : undefined}
      />
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" disabled={!actorIsSupreme}>
        Update delegation
      </Button>
      <ErrorBanner id={`sched-delegation-${task.taskCode}-error`} error={state.error} />
    </form>
  );
}

export function ScheduledTaskList({
  tenantSlug,
  tasks,
  actorIsSupreme,
}: {
  tenantSlug: string;
  tasks: readonly TenantScheduledTask[];
  actorIsSupreme: boolean;
}) {
  if (tasks.length === 0) {
    return <EmptyState title="No automatic tasks are offered yet" description="The platform has not published any schedulable tasks for this organisation." />;
  }

  return (
    <ul className="space-y-3">
      {tasks.map((task) => (
        <li key={task.taskCode} className="rounded-lg border border-neutral-200 p-4">
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <h3 className="text-sm font-semibold text-text-primary">{task.displayName}</h3>
              <p className="mt-1 max-w-2xl text-sm text-text-secondary">{task.description}</p>
            </div>
            <div className="flex items-center gap-2">
              <StatusBadge tone={task.enabled ? "success" : "neutral"} label={task.enabled ? "On" : "Off"} />
              {task.lastRunStatus ? <StatusBadge tone={RUN_STATUS_TONE[task.lastRunStatus]} label={task.lastRunStatus} /> : null}
            </div>
          </div>

          {/* The auto-disable case gets its own explanation rather than a status pill, because
              "your automation silently stopped" is the failure a reader most needs to understand,
              and the fix — somebody with current authority switches it back on — is not obvious
              from the word "disabled". */}
          {task.disabledReason ? (
            <div className="mt-3 rounded-md border border-status-warning-subtle bg-status-warning-subtle p-3 text-xs text-status-warning-strong">
              <strong>This task stopped running.</strong> {task.disabledReason}
              <p className="mt-1">
                A scheduled task runs with the permissions of the person who switched it on. When those permissions
                change — someone changes role, or leaves — the task stops rather than carrying on with authority
                nobody holds any more. Switching it back on below makes it run as you.
              </p>
            </div>
          ) : null}

          <dl className="mt-3 grid grid-cols-2 gap-x-6 gap-y-1 text-xs text-text-secondary sm:grid-cols-4">
            <div>
              <dt className="font-medium">Frequency</dt>
              <dd>{humaniseInterval(task.intervalMinutes)}</dd>
            </div>
            <div>
              <dt className="font-medium">Next run</dt>
              <dd>{task.enabled ? formatInstant(task.nextRunAt) : "—"}</dd>
            </div>
            <div>
              <dt className="font-medium">Last run</dt>
              <dd>{formatInstant(task.lastRunAt)}</dd>
            </div>
            <div>
              <dt className="font-medium">Runs as</dt>
              <dd className="font-mono">{task.authorizedByAuthUserId ?? "—"}</dd>
            </div>
          </dl>

          {task.lastRunDetail ? (
            <p className="mt-2 break-words rounded-md bg-surface-muted p-2 font-mono text-xs text-text-secondary">{task.lastRunDetail}</p>
          ) : null}

          {!task.configurableByActor ? (
            <p className="mt-3 text-xs text-text-secondary">
              This task is managed by CargoGrid. A Supreme Admin decides whether organisation admins may change it.
            </p>
          ) : null}

          <ScheduleForm tenantSlug={tenantSlug} task={task} />
          <DelegationForm tenantSlug={tenantSlug} task={task} actorIsSupreme={actorIsSupreme} />
        </li>
      ))}
    </ul>
  );
}
