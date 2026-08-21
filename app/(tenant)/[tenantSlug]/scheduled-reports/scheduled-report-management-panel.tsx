"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { ScheduledReportActionState } from "./actions.ts";
import type { ScheduledReport, ScheduledReportStatus } from "../../../../server/contracts/scheduled-report/scheduled-report.ts";
import type { ReportType } from "../../../../server/contracts/report/report.ts";

const INITIAL_STATE: ScheduledReportActionState = { error: null };

const STATUS_TONE: Record<ScheduledReportStatus, StatusTone> = {
  active: "success",
  paused: "warning",
  archived: "neutral",
};

export function ScheduledReportManagementPanel({
  tenantSlug,
  schedules,
  reportTypes,
  createAction,
}: {
  tenantSlug: string;
  schedules: readonly ScheduledReport[];
  reportTypes: readonly ReportType[];
  createAction: (prevState: ScheduledReportActionState, formData: FormData) => Promise<ScheduledReportActionState>;
}) {
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {schedules.length === 0 ? (
          <EmptyState title="No scheduled reports yet" description="Create one below." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Name</th>
                <th className="pb-1">Report</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Next run</th>
              </tr>
            </thead>
            <tbody>
              {schedules.map((s) => (
                <tr key={s.id} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/scheduled-reports/${s.id}`} className="text-primary underline">
                      {s.name}
                    </Link>
                  </td>
                  <td className="py-1">{reportTypes.find((t) => t.code === s.reportTypeCode)?.name ?? s.reportTypeCode}</td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[s.status]} label={s.status} />
                  </td>
                  <td className="py-1">{s.nextRunAt}</td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new scheduled report</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div className="flex flex-col gap-1 sm:col-span-2">
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
            <label htmlFor="name" className="text-xs font-medium text-neutral-600">
              Name
            </label>
            <input id="name" name="name" type="text" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="cronHour" className="text-xs font-medium text-neutral-600">
              Hour (0-23)
            </label>
            <input id="cronHour" name="cronHour" type="number" min={0} max={23} defaultValue={9} required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="cronMinute" className="text-xs font-medium text-neutral-600">
              Minute (0-59)
            </label>
            <input id="cronMinute" name="cronMinute" type="number" min={0} max={59} defaultValue={0} required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="timezone" className="text-xs font-medium text-neutral-600">
              Timezone (IANA)
            </label>
            <input id="timezone" name="timezone" type="text" placeholder="Asia/Jakarta" defaultValue="Asia/Jakarta" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="cronDayOfWeek" className="text-xs font-medium text-neutral-600">
              Day of week (0=Sun, blank=daily)
            </label>
            <input id="cronDayOfWeek" name="cronDayOfWeek" type="number" min={0} max={6} placeholder="blank = daily" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="cronDayOfMonth" className="text-xs font-medium text-neutral-600">
              Day of month (1-28, blank=daily/weekly)
            </label>
            <input id="cronDayOfMonth" name="cronDayOfMonth" type="number" min={1} max={28} placeholder="blank = daily/weekly" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
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
              Create schedule
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
