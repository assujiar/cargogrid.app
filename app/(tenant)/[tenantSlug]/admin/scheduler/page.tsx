import { notFound } from "next/navigation";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import {
  listTenantScheduledTasks,
  TaskSchedulerQueryError,
  type TaskSchedulerQueryRpcClient,
} from "../../../../../server/queries/task-scheduler.ts";
import type { TenantScheduledTask } from "../../../../../server/contracts/task-scheduler/task-scheduler.ts";
import { ErrorState } from "../../../../../components/ui/error-state.tsx";
import { ScheduledTaskList } from "./scheduler-admin-panel.tsx";

/**
 * Automation console — the configuration surface for the task scheduler
 * (`20260831090000_create_tenant_configurable_task_scheduler.sql`).
 *
 * Eleven backlog entries shared one sentence: some form of "on-demand/staff-triggered only; no
 * automatic job wires this up". Loyalty points did not expire on their own, incidents did not
 * escalate on their own, leave did not accrue on its own. The sweeps all existed and all worked —
 * nothing ever called them on a timer.
 *
 * The reason that was not simply a cron entry is worth stating, because it shaped this page:
 * every sweep takes an actor and most check that actor's permissions, and a cron job has no
 * identity. Rather than mint a robot account with standing authority, a scheduled task here runs
 * **as the person who switched it on**, whose authority is re-checked on every run. That makes
 * this page a governance surface as much as a settings screen, which is why it shows who each
 * task runs as and explains plainly what happens when that person's access changes.
 *
 * Supreme Admin owns the catalogue and decides, per task type, whether an organisation's own
 * admin may configure it; the organisation then tunes its own frequency. Both halves are visible
 * here, and both are enforced by the RPCs rather than by this page.
 */

function toQueryClient(client: Awaited<ReturnType<typeof createSupabaseServerClient>>): TaskSchedulerQueryRpcClient {
  return client as unknown as TaskSchedulerQueryRpcClient;
}

/**
 * Derived from the RPC's own per-row answer rather than re-deciding it here. Only a Supreme Admin
 * can configure a task that has NOT been delegated to organisation admins, so one such row is
 * proof. Deriving it this way means the page cannot drift from
 * `app._can_configure_tenant_scheduled_task`, which a second authority check in TypeScript would.
 */
function actorIsSupremeAdmin(tasks: readonly TenantScheduledTask[]): boolean {
  return tasks.some((task) => task.configurableByActor && !task.tenantAdminConfigurable);
}

export default async function SchedulerAdminPage({ params }: { params: Promise<{ tenantSlug: string }> }) {
  const { tenantSlug } = await params;
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    notFound();
  }

  let tasks: TenantScheduledTask[] = [];
  let loadError: string | null = null;
  try {
    tasks = await listTenantScheduledTasks(toQueryClient(await createSupabaseServerClient()), {
      tenantId: access.tenant.id,
      actorAuthUserId: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TaskSchedulerQueryError) {
      loadError = error.message;
    } else {
      throw error;
    }
  }

  const isSupreme = actorIsSupremeAdmin(tasks);
  const running = tasks.filter((task) => task.enabled).length;
  const stopped = tasks.filter((task) => task.disabledReason !== null && !task.enabled).length;

  return (
    <div className="space-y-6">
      <header>
        <h1 className="text-lg font-semibold text-text-primary">Automatic tasks</h1>
        <p className="mt-1 max-w-3xl text-sm text-text-secondary">
          Routine work CargoGrid can run for you on a timer — expiring loyalty points, escalating
          overdue incidents, accruing leave, reminding people about certificates that are about to
          lapse. Each task runs with the permissions of whoever switches it on, and every run is
          recorded against that person.
        </p>
      </header>

      {loadError ? (
        <ErrorState title="Could not load automatic tasks" description={loadError} />
      ) : (
        <>
          <div className="flex flex-wrap gap-6 rounded-lg border border-neutral-200 p-4 text-sm">
            <div>
              <p className="text-xs font-medium text-text-secondary">Running automatically</p>
              <p className="text-lg font-semibold text-text-primary">{running}</p>
            </div>
            <div>
              <p className="text-xs font-medium text-text-secondary">Available in total</p>
              <p className="text-lg font-semibold text-text-primary">{tasks.length}</p>
            </div>
            {stopped > 0 ? (
              <div>
                <p className="text-xs font-medium text-status-warning-strong">Stopped and needing attention</p>
                <p className="text-lg font-semibold text-status-warning-strong">{stopped}</p>
              </div>
            ) : null}
          </div>

          {/* Said once, at the top, rather than repeated per row: the single fact that explains
              both why a task can stop by itself and why switching it back on is a real act. */}
          <div className="rounded-lg border border-neutral-200 bg-surface-muted p-4 text-sm text-text-secondary">
            <p>
              <strong className="text-text-primary">Why a task can stop on its own.</strong> A scheduled task acts on
              behalf of the person who switched it on — it does not have permissions of its own. If that person&apos;s
              access changes or they leave, the task stops instead of continuing with authority nobody holds. Switching
              it on again transfers it to you.
            </p>
            {!isSupreme ? (
              <p className="mt-2">
                Some tasks are managed by CargoGrid and cannot be changed here. A Supreme Admin decides which ones your
                organisation may configure for itself.
              </p>
            ) : null}
          </div>

          <ScheduledTaskList tenantSlug={tenantSlug} tasks={tasks} actorIsSupreme={isSupreme} />
        </>
      )}
    </div>
  );
}
