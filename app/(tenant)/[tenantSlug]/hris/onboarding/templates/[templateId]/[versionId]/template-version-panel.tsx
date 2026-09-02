"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../../../components/forms/validation-message.tsx";
import { useUnsavedFormGuard } from "../../../../../../../../components/forms/use-unsaved-change-guard.ts";
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
  // ISS-2026-070 item 5: unsaved-change protection on the two multi-field authoring forms.
  // The publish form carries no user input at all, so it needs no guard.
  const { dirty: addTaskDirty, formProps: addTaskFormProps } = useUnsavedFormGuard(addTaskPending, addTaskState.error);
  const { dirty: addDepDirty, formProps: addDepFormProps } = useUnsavedFormGuard(addDepPending, addDepState.error);

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
      {publishState.error ? <ValidationMessage>{publishState.error}</ValidationMessage> : null}
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
        <form action={addTaskFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-3" noValidate {...addTaskFormProps}>
          <label htmlFor="task-key" className="sr-only">
            Task key
          </label>
          <Input id="task-key" name="taskKey" placeholder="task key (e.g. it-access)" required pattern="[a-z0-9_-]{2,64}" invalid={Boolean(addTaskState.error)} aria-describedby={addTaskState.error ? "add-task-error" : undefined} />
          <label htmlFor="task-title" className="sr-only">
            Title
          </label>
          <Input id="task-title" name="title" placeholder="Title" required invalid={Boolean(addTaskState.error)} aria-describedby={addTaskState.error ? "add-task-error" : undefined} />
          <label htmlFor="task-type" className="sr-only">
            Task type
          </label>
          <Select id="task-type" name="taskType" required defaultValue="generic" invalid={Boolean(addTaskState.error)} aria-describedby={addTaskState.error ? "add-task-error" : undefined}>
            {TASK_TYPES.map((t) => (
              <option key={t} value={t}>
                {t.replace(/_/g, " ")}
              </option>
            ))}
          </Select>
          <label htmlFor="task-handoff-category" className="sr-only">
            Handoff category
          </label>
          <Select id="task-handoff-category" name="handoffCategory" defaultValue="" invalid={Boolean(addTaskState.error)} aria-describedby={addTaskState.error ? "add-task-error" : undefined}>
            <option value="">No handoff category</option>
            {HANDOFF_CATEGORIES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </Select>
          <label htmlFor="task-owner-type" className="sr-only">
            Owner type
          </label>
          <Select id="task-owner-type" name="ownerType" required defaultValue="hr" invalid={Boolean(addTaskState.error)} aria-describedby={addTaskState.error ? "add-task-error" : undefined}>
            {OWNER_TYPES.map((o) => (
              <option key={o} value={o}>
                {o}
              </option>
            ))}
          </Select>
          <label htmlFor="task-sla-days" className="sr-only">
            SLA days
          </label>
          <Input id="task-sla-days" name="slaDays" type="number" min="1" defaultValue="3" invalid={Boolean(addTaskState.error)} aria-describedby={addTaskState.error ? "add-task-error" : undefined} />
          <label htmlFor="task-sort-order" className="sr-only">
            Sort order
          </label>
          <Input id="task-sort-order" name="sortOrder" type="number" defaultValue={realTasks.length + 1} invalid={Boolean(addTaskState.error)} aria-describedby={addTaskState.error ? "add-task-error" : undefined} />
          <Checkbox id="task-is-mandatory" name="isMandatory" defaultChecked label="Mandatory" aria-describedby={addTaskState.error ? "add-task-error" : undefined} />
          {addTaskState.error ? (
            <div className="col-span-full">
              <ValidationMessage id="add-task-error">{addTaskState.error}</ValidationMessage>
            </div>
          ) : null}
          {addTaskDirty ? <p className="col-span-full text-xs text-warning">You have unsaved changes.</p> : null}
          <div className="col-span-full">
            <Button type="submit" variant="secondary" loading={addTaskPending} loadingLabel="Adding…">
              Add task
            </Button>
          </div>
        </form>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Add a dependency</h2>
        <form action={addDepFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-3" noValidate {...addDepFormProps}>
          <label htmlFor="dep-task-key" className="sr-only">
            Task key
          </label>
          <Input id="dep-task-key" name="taskKey" placeholder="task key (depends)" required invalid={Boolean(addDepState.error)} aria-describedby={addDepState.error ? "add-dep-error" : undefined} />
          <label htmlFor="dep-depends-on" className="sr-only">
            Depends on task key
          </label>
          <Input id="dep-depends-on" name="dependsOnTaskKey" placeholder="depends on task key" required invalid={Boolean(addDepState.error)} aria-describedby={addDepState.error ? "add-dep-error" : undefined} />
          {addDepState.error ? (
            <div className="col-span-full">
              <ValidationMessage id="add-dep-error">{addDepState.error}</ValidationMessage>
            </div>
          ) : null}
          {addDepDirty ? <p className="col-span-full text-xs text-warning">You have unsaved changes.</p> : null}
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
