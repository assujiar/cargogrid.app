"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../../../components/ui/empty-state.tsx";
import type { TemplateActionState } from "../../actions.ts";
import { TASK_TYPES, HANDOFF_CATEGORIES, OWNER_TYPES, type OnboardingChecklistTemplateTask } from "../../../../../../../../server/contracts/onboarding/onboarding.ts";

const INITIAL_STATE: TemplateActionState = { error: null };
type BoundAction = (prevState: TemplateActionState, formData: FormData) => Promise<TemplateActionState>;

export function TemplateVersionPanel({
  tenantSlug: _tenantSlug,
  templateId: _templateId,
  versionId: _versionId,
  tasks,
  addTaskAction,
  addDependencyAction,
  publishAction,
}: {
  tenantSlug: string;
  templateId: string;
  versionId: string;
  tasks: readonly OnboardingChecklistTemplateTask[];
  addTaskAction: BoundAction;
  addDependencyAction: BoundAction;
  publishAction: (expectedVersion: number) => BoundAction;
}) {
  const realTasks = tasks.filter((t) => t.taskId != null);
  const versionHeader = tasks[0];
  const [addTaskState, addTaskFormAction, addTaskPending] = useActionState(addTaskAction, INITIAL_STATE);
  const [addDepState, addDepFormAction, addDepPending] = useActionState(addDependencyAction, INITIAL_STATE);
  const boundPublish = versionHeader ? publishAction(versionHeader.versionRecordVersion) : null;
  const [publishState, publishFormAction, publishPending] = useActionState(boundPublish ?? (async (_s: TemplateActionState) => INITIAL_STATE), INITIAL_STATE);

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-semibold text-neutral-900">Template draft version {versionHeader ? `v${versionHeader.versionNumber}` : ""}</h1>
          {versionHeader ? <StatusBadge tone={versionHeader.status === "published" ? "success" : "neutral"} label={versionHeader.status} /> : null}
        </div>
        {versionHeader && versionHeader.status === "draft" ? (
          <form action={publishFormAction}>
            <Button type="submit" loading={publishPending} loadingLabel="Publishing…" disabled={realTasks.length === 0}>
              Publish version
            </Button>
          </form>
        ) : null}
      </div>
      {publishState.error ? (
        <p role="alert" className="text-sm text-danger">
          {publishState.error}
        </p>
      ) : null}
      {realTasks.length === 0 ? <p className="text-xs text-warning">A version needs at least one task before it can be published.</p> : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Tasks</h2>
        {realTasks.length === 0 ? (
          <EmptyState title="No tasks yet" description="Add a task below." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Key</th>
                  <th className="pb-1">Title</th>
                  <th className="pb-1">Type</th>
                  <th className="pb-1">Owner</th>
                  <th className="pb-1">Mandatory</th>
                  <th className="pb-1">SLA (days)</th>
                  <th className="pb-1">Depends on</th>
                </tr>
              </thead>
              <tbody>
                {realTasks.map((t) => (
                  <tr key={t.taskId} className="border-t border-neutral-100">
                    <td className="py-1 font-mono text-xs">{t.taskKey}</td>
                    <td className="py-1">{t.title}</td>
                    <td className="py-1 text-xs">
                      {t.taskType?.replace(/_/g, " ")}
                      {t.handoffCategory ? ` — ${t.handoffCategory}` : ""}
                    </td>
                    <td className="py-1 text-xs">{t.ownerType}</td>
                    <td className="py-1 text-xs">{t.isMandatory ? "yes" : "no"}</td>
                    <td className="py-1 text-xs">{t.slaDays}</td>
                    <td className="py-1 text-xs">{t.dependsOnTaskKeys.join(", ") || "—"}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Add a task</h2>
        <form action={addTaskFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <input name="taskKey" placeholder="task key (e.g. it-access)" required pattern="[a-z0-9_-]{2,64}" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="title" placeholder="Title" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <select name="taskType" required defaultValue="generic" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            {TASK_TYPES.map((t) => (
              <option key={t} value={t}>
                {t.replace(/_/g, " ")}
              </option>
            ))}
          </select>
          <select name="handoffCategory" defaultValue="" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            <option value="">No handoff category</option>
            {HANDOFF_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
          <select name="ownerType" required defaultValue="hr" className="rounded-md border border-neutral-300 px-2 py-1 text-sm">
            {OWNER_TYPES.map((o) => (
              <option key={o} value={o}>
                {o}
              </option>
            ))}
          </select>
          <input name="slaDays" type="number" min="1" defaultValue="3" className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="sortOrder" type="number" defaultValue={realTasks.length + 1} className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <label className="flex items-center gap-2 text-xs text-neutral-600">
            <input type="checkbox" name="isMandatory" defaultChecked /> Mandatory
          </label>
          {addTaskState.error ? (
            <p role="alert" className="col-span-full text-xs text-danger">
              {addTaskState.error}
            </p>
          ) : null}
          <div className="col-span-full">
            <Button type="submit" variant="secondary" loading={addTaskPending} loadingLabel="Adding…">
              Add task
            </Button>
          </div>
        </form>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Add a dependency</h2>
        <form action={addDepFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <input name="taskKey" placeholder="task key (depends)" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          <input name="dependsOnTaskKey" placeholder="depends on task key" required className="rounded-md border border-neutral-300 px-2 py-1 text-sm" />
          {addDepState.error ? (
            <p role="alert" className="col-span-full text-xs text-danger">
              {addDepState.error}
            </p>
          ) : null}
          <div className="col-span-full">
            <Button type="submit" variant="secondary" loading={addDepPending} loadingLabel="Adding…">
              Add dependency
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
