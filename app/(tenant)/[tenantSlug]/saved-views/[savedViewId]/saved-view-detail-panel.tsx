"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge } from "../../../../../components/ui/status-badge.tsx";
import type { SavedReportViewActionState } from "../actions.ts";
import type { SavedReportView } from "../../../../../server/contracts/saved-report-view/saved-report-view.ts";
import type { ReportType } from "../../../../../server/contracts/report/report.ts";

const INITIAL_STATE: SavedReportViewActionState = { error: null };

type BoundFormAction = (prevState: SavedReportViewActionState, formData: FormData) => Promise<SavedReportViewActionState>;

export function SavedViewDetailPanel({
  view,
  reportType,
  isOwner,
  isStale,
  updateAction,
  deleteAction,
  exportAction,
}: {
  view: SavedReportView;
  reportType: ReportType | null;
  isOwner: boolean;
  isStale: boolean;
  updateAction: BoundFormAction;
  deleteAction: BoundFormAction;
  exportAction: BoundFormAction;
}) {
  const [updateState, updateFormAction, updatePending] = useActionState(updateAction, INITIAL_STATE);
  const [deleteState, deleteFormAction, deletePending] = useActionState(deleteAction, INITIAL_STATE);
  const [exportState, exportFormAction, exportPending] = useActionState(exportAction, INITIAL_STATE);
  const updateDescribedBy = updateState.error ? "saved-view-update-error" : undefined;

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">{view.name}</h1>
        <StatusBadge tone={view.sharingScope === "tenant" ? "info" : "neutral"} label={view.sharingScope === "tenant" ? "shared" : "private"} />
        {isStale ? <StatusBadge tone="warning" label="report definition changed since this view was last saved" /> : null}
      </header>
      <p className="text-xs text-neutral-500">
        Report: {reportType?.name ?? view.reportTypeCode} · Columns: {view.columns.join(", ")}
      </p>
      {view.description ? <p className="text-xs text-neutral-500">{view.description}</p> : null}

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-neutral-900">Export</h2>
        <p className="mb-2 text-xs text-neutral-500">Runs this view&apos;s own report/parameters through the existing export pipeline. Reauthorizes at run time -- sharing this view never granted you access on its own.</p>
        <form action={exportFormAction} className="flex flex-col gap-2">
          {exportState.error ? (
            <p role="alert" className="text-sm text-danger">
              {exportState.error}
            </p>
          ) : null}
          <Button type="submit" variant="secondary" loading={exportPending} loadingLabel="Exporting…" className="w-fit">
            Export
          </Button>
        </form>
      </section>

      {isOwner ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Edit</h2>
          <form action={updateFormAction} className="flex flex-col gap-3">
            {/* ISS-2026-242: these four controls had no label of any kind -- not even a
                placeholder. The labels match the create form's own wording for the same
                four fields, so the two forms now read identically. */}
            <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
              <FormField id="saved-view-edit-name" label="Name">
                <Input
                  id="saved-view-edit-name"
                  name="name"
                  defaultValue={view.name}
                  required
                  invalid={Boolean(updateState.error)}
                  aria-describedby={updateDescribedBy}
                />
              </FormField>
              <FormField id="saved-view-edit-columns" label="Columns (comma-separated)">
                <Input
                  id="saved-view-edit-columns"
                  name="columns"
                  defaultValue={view.columns.join(", ")}
                  required
                  invalid={Boolean(updateState.error)}
                  aria-describedby={updateDescribedBy}
                />
              </FormField>
              <div className="sm:col-span-2">
                <FormField id="saved-view-edit-filters" label="Filters (JSON object, matches the report's own run parameters)">
                  <Textarea
                    id="saved-view-edit-filters"
                    name="filters"
                    defaultValue={JSON.stringify(view.filters)}
                    rows={2}
                    className="font-mono"
                    invalid={Boolean(updateState.error)}
                    aria-describedby={updateDescribedBy}
                  />
                </FormField>
              </div>
              <div className="sm:col-span-2">
                <FormField id="saved-view-edit-description" label="Description (optional)">
                  <Textarea
                    id="saved-view-edit-description"
                    name="description"
                    defaultValue={view.description ?? ""}
                    rows={2}
                    invalid={Boolean(updateState.error)}
                    aria-describedby={updateDescribedBy}
                  />
                </FormField>
              </div>
            </div>
            {updateState.error ? <ValidationMessage id="saved-view-update-error">{updateState.error}</ValidationMessage> : null}
            <Button type="submit" variant="secondary" loading={updatePending} loadingLabel="Saving…" className="w-fit">
              Save changes
            </Button>
          </form>
        </section>
      ) : null}

      {isOwner ? (
        <section className="rounded-md border border-neutral-200 p-4">
          <h2 className="mb-2 text-sm font-semibold text-neutral-900">Delete</h2>
          <form action={deleteFormAction} className="flex flex-col gap-2">
            {deleteState.error ? (
              <p role="alert" className="text-sm text-danger">
                {deleteState.error}
              </p>
            ) : null}
            <Button type="submit" variant="destructive" loading={deletePending} loadingLabel="Deleting…" className="w-fit">
              Delete saved view
            </Button>
          </form>
        </section>
      ) : null}
    </div>
  );
}
