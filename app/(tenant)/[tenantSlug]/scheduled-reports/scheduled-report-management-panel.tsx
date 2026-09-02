"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../components/forms/number-input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Textarea } from "../../../../components/forms/textarea.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
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
  const describedBy = state.error ? "create-scheduled-report-error" : undefined;

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        {schedules.length === 0 ? (
          <EmptyState title="No scheduled reports yet" description="Create one below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] text-sm">
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
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Create a new scheduled report</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-3">
          <div className="sm:col-span-2">
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
          </div>
          <FormField id="name" label="Name">
            <Input id="name" name="name" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="cronHour" label="Hour (0-23)">
            <NumberInput id="cronHour" name="cronHour" min={0} max={23} defaultValue={9} required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="cronMinute" label="Minute (0-59)">
            <NumberInput id="cronMinute" name="cronMinute" min={0} max={59} defaultValue={0} required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="timezone" label="Timezone (IANA)">
            <Input id="timezone" name="timezone" type="text" placeholder="Asia/Jakarta" defaultValue="Asia/Jakarta" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="cronDayOfWeek" label="Day of week (0=Sun, blank=daily)">
            <NumberInput id="cronDayOfWeek" name="cronDayOfWeek" min={0} max={6} placeholder="blank = daily" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
          <FormField id="cronDayOfMonth" label="Day of month (1-28, blank=daily/weekly)">
            <NumberInput id="cronDayOfMonth" name="cronDayOfMonth" min={1} max={28} placeholder="blank = daily/weekly" invalid={Boolean(state.error)} aria-describedby={describedBy} />
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
              <ValidationMessage id="create-scheduled-report-error">{state.error}</ValidationMessage>
            </div>
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
