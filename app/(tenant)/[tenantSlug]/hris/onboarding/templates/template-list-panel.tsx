"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import { useUnsavedFormGuard } from "../../../../../../components/forms/use-unsaved-change-guard.ts";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../../components/ui/empty-state.tsx";
import type { TemplateActionState } from "./actions.ts";
import { CASE_TYPES, type TemplateListRow } from "../../../../../../server/contracts/onboarding/onboarding.ts";

const INITIAL_STATE: TemplateActionState = { error: null };
type BoundAction = (prevState: TemplateActionState, formData: FormData) => Promise<TemplateActionState>;

export function TemplateListPanel({
  tenantSlug,
  templates,
  createAction,
  openDraftAction,
}: {
  tenantSlug: string;
  templates: readonly TemplateListRow[];
  createAction: BoundAction;
  openDraftAction: (templateId: string) => BoundAction;
}) {
  const [createState, createFormAction, createPending] = useActionState(createAction, INITIAL_STATE);
  // ISS-2026-070 item 5: unsaved-change protection on the template-authoring forms.
  const { dirty: createDirty, formProps: createFormProps } = useUnsavedFormGuard(createPending, createState.error);

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {templates.length === 0 ? (
          <EmptyState title="No templates yet" description="Create a template below, then add tasks and publish a version." />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Code</th>
                  <th className="pb-1">Name</th>
                  <th className="pb-1">Case type</th>
                  <th className="pb-1">Published version</th>
                  <th className="pb-1">Action</th>
                </tr>
              </thead>
              <tbody>
                {templates.map((t) => (
                  <TemplateRow key={t.id} template={t} openDraftAction={openDraftAction(t.id)} />
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new template</h2>
        <form action={createFormAction} className="grid grid-cols-1 gap-2 sm:grid-cols-4" noValidate {...createFormProps}>
          <label htmlFor="template-code" className="sr-only">
            Code
          </label>
          <Input id="template-code" name="code" placeholder="Code (e.g. ONB-STD)" required invalid={Boolean(createState.error)} aria-describedby={createState.error ? "template-create-error" : undefined} />
          <label htmlFor="template-name" className="sr-only">
            Name
          </label>
          <Input id="template-name" name="name" placeholder="Name" required invalid={Boolean(createState.error)} aria-describedby={createState.error ? "template-create-error" : undefined} />
          <label htmlFor="template-case-type" className="sr-only">
            Case type
          </label>
          <Select id="template-case-type" name="caseType" required defaultValue="onboarding" invalid={Boolean(createState.error)} aria-describedby={createState.error ? "template-create-error" : undefined}>
            {CASE_TYPES.map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </Select>
          {createState.error ? (
            <div className="col-span-full">
              <ValidationMessage id="template-create-error">{createState.error}</ValidationMessage>
            </div>
          ) : null}
          {createDirty ? <p className="col-span-full text-xs text-warning">You have unsaved changes.</p> : null}
          <div className="col-span-full">
            <Button type="submit" variant="secondary" loading={createPending} loadingLabel="Creating…">
              Create template
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}

function TemplateRow({ template, openDraftAction }: { template: TemplateListRow; openDraftAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(openDraftAction, INITIAL_STATE);

  return (
    <tr className="border-t border-neutral-100 align-top">
      <td className="py-1">{template.code}</td>
      <td className="py-1">{template.name}</td>
      <td className="py-1 text-xs">{template.caseType}</td>
      <td className="py-1 text-xs">{template.publishedVersionNumber != null ? `v${template.publishedVersionNumber}` : <StatusBadge tone="warning" label="none published" />}</td>
      <td className="py-1">
        <form action={formAction} className="flex flex-col gap-1">
          <Button type="submit" variant="secondary" loading={pending} loadingLabel="Opening…">
            Manage draft version
          </Button>
          {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
        </form>
      </td>
    </tr>
  );
}
