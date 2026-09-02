"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Textarea } from "../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import { StatusBadge } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { SavedReportViewActionState } from "./actions.ts";
import type { SavedReportView } from "../../../../server/contracts/saved-report-view/saved-report-view.ts";
import type { ReportType } from "../../../../server/contracts/report/report.ts";

const INITIAL_STATE: SavedReportViewActionState = { error: null };

export function SavedViewManagementPanel({
  tenantSlug,
  views,
  reportTypes,
  ownerAuthUserId,
  createAction,
}: {
  tenantSlug: string;
  views: readonly SavedReportView[];
  reportTypes: readonly ReportType[];
  ownerAuthUserId: string;
  createAction: (prevState: SavedReportViewActionState, formData: FormData) => Promise<SavedReportViewActionState>;
}) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);
  const describedBy = state.error ? "create-saved-view-error" : undefined;

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {views.length === 0 ? (
          <EmptyState title="No saved views yet" description="Create your first one below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Name</th>
                <th className="pb-1">Report</th>
                <th className="pb-1">Sharing</th>
                <th className="pb-1">Owner</th>
              </tr>
            </thead>
            <tbody>
              {views.map((v) => (
                <tr key={v.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/saved-views/${v.id}`} className="text-primary underline">
                      {v.name}
                    </Link>
                  </td>
                  <td className="py-1">{reportTypes.find((t) => t.code === v.reportTypeCode)?.name ?? v.reportTypeCode}</td>
                  <td className="py-1">
                    <StatusBadge tone={v.sharingScope === "tenant" ? "info" : "neutral"} label={v.sharingScope === "tenant" ? "shared" : "private"} />
                  </td>
                  <td className="py-1">{v.ownerAuthUserId === ownerAuthUserId ? "you" : (v.ownerLabel ?? "—")}</td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new saved view</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <FormField id="reportTypeCode" label="Report">
            <Select id="reportTypeCode" name="reportTypeCode" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
              <option value="">Select a report…</option>
              {reportTypes.map((t) => (
                <option key={t.code} value={t.code}>
                  {t.name}
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="sharingScope" label="Sharing">
            <Select id="sharingScope" name="sharingScope" defaultValue="private" invalid={Boolean(state.error)} aria-describedby={describedBy}>
              <option value="private">Private (only me)</option>
              <option value="tenant">Shared with the tenant (requires REP:Configure)</option>
            </Select>
          </FormField>
          <FormField id="name" label="Name">
            <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="columns" label="Columns (comma-separated)">
            <Input id="columns" name="columns" type="text" placeholder="invoiceNumber, amount, dueDate" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <div className="col-span-full">
            <FormField id="filters" label="Filters (JSON object, matches the report's own run parameters)">
              <Textarea id="filters" name="filters" rows={2} placeholder="{}" className="font-mono" invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>
          <div className="col-span-full">
            <FormField id="description" label="Description (optional)">
              <Textarea id="description" name="description" rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
            </FormField>
          </div>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id="create-saved-view-error">{state.error}</ValidationMessage>
            </div>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Creating…">
              Create saved view
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
