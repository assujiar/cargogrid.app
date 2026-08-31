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

function ErrorBanner({ error }: { error: string | null }) {
  if (!error) return null;
  return <p className="mt-2 text-xs text-status-danger-strong">{error}</p>;
}

function SavedNote({ state }: { state: SchedulerFormState }) {
  if (!state.saved) return null;
  return <p className="mt-2 text-xs text-status-success-strong">Saved. This schedule now runs as you.</p>;
}

function ScheduleForm({ tenantSlug, task }: { tenantSlug: string; task: TenantScheduledTask }) {
  const boundAction = configureScheduledTaskAction.bind(null, tenantSlug);
  const [state, formAction, pending] = useActionState(boundAction, SCHEDULER_INITIAL_STATE);

  return (
    <form action={formAction} className="mt-3 flex flex-wrap items-end gap-3">
      <input type="hidden" name="taskCode" value={task.taskCode} />
      <input type="hidden" name="requiredParams" value={task.requiredParams.join(",")} />

      <label className="flex items-center gap-2 text-sm text-text-primary">
        <input
          type="checkbox"
          name="enabled"
          defaultChecked={task.enabled}
          disabled={!task.configurableByActor}
          className="h-4 w-4"
        />
        Run automatically
      </label>

      <label className="flex flex-col gap-1 text-xs text-text-secondary">
        How often (minutes)
        <input
          type="number"
          name="intervalMinutes"
          min={task.minIntervalMinutes}
          step={1}
          defaultValue={task.intervalMinutes ?? task.defaultIntervalMinutes}
          disabled={!task.configurableByActor}
          className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-sm text-text-primary"
        />
        <span>No more often than every {task.minIntervalMinutes} min</span>
      </label>

      {task.requiredParams.map((key) => (
        <label key={key} className="flex flex-col gap-1 text-xs text-text-secondary">
          {key.replace(/_/g, " ")}
          <input
            type="text"
            name={`param_${key}`}
            defaultValue={String(task.params[key] ?? "")}
            disabled={!task.configurableByActor}
            className="w-64 rounded-md border border-neutral-300 px-2 py-1 text-sm text-text-primary"
          />
        </label>
      ))}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" disabled={!task.configurableByActor}>
        Save
      </Button>

      <ErrorBanner error={state.error} />
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
      <label className="flex items-center gap-2 text-text-secondary">
        <input
          type="checkbox"
          name="tenantAdminConfigurable"
          defaultChecked={task.tenantAdminConfigurable}
          disabled={!actorIsSupreme}
          className="h-4 w-4"
        />
        Organisation admins may configure this
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" disabled={!actorIsSupreme}>
        Update delegation
      </Button>
      <ErrorBanner error={state.error} />
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
