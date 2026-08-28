"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
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
          <div className="flex flex-col gap-1">
            <label htmlFor="reportTypeCode" className="text-xs font-medium text-neutral-600">
              Report
            </label>
            <select id="reportTypeCode" name="reportTypeCode" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              <option value="">Select a report…</option>
              {reportTypes.map((t) => (
                <option key={t.code} value={t.code}>
                  {t.name}
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="sharingScope" className="text-xs font-medium text-neutral-600">
              Sharing
            </label>
            <select id="sharingScope" name="sharingScope" defaultValue="private" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              <option value="private">Private (only me)</option>
              <option value="tenant">Shared with the tenant (requires REP:Configure)</option>
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="name" className="text-xs font-medium text-neutral-600">
              Name
            </label>
            <input id="name" name="name" type="text" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="columns" className="text-xs font-medium text-neutral-600">
              Columns (comma-separated)
            </label>
            <input id="columns" name="columns" type="text" placeholder="invoiceNumber, amount, dueDate" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="col-span-full flex flex-col gap-1">
            <label htmlFor="filters" className="text-xs font-medium text-neutral-600">
              Filters (JSON object, matches the report&apos;s own run parameters)
            </label>
            <textarea id="filters" name="filters" rows={2} placeholder="{}" className="rounded-md border border-neutral-300 px-3 py-1.5 font-mono text-sm" />
          </div>
          <div className="col-span-full flex flex-col gap-1">
            <label htmlFor="description" className="text-xs font-medium text-neutral-600">
              Description (optional)
            </label>
            <textarea id="description" name="description" rows={2} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
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
