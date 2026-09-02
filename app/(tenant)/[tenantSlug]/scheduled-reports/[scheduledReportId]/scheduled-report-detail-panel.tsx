"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { ScheduledReportActionState } from "../actions.ts";
import type { ScheduledReport, ScheduledReportRecipient, ScheduledReportRun, ScheduledReportStatus } from "../../../../../server/contracts/scheduled-report/scheduled-report.ts";

const INITIAL_STATE: ScheduledReportActionState = { error: null };

const STATUS_TONE: Record<ScheduledReportStatus, StatusTone> = {
  active: "success",
  paused: "warning",
  archived: "neutral",
};

const RUN_STATUS_TONE: Record<ScheduledReportRun["status"], StatusTone> = {
  queued: "info",
  completed: "success",
  failed: "danger",
};

type BoundFormAction = (prevState: ScheduledReportActionState, formData: FormData) => Promise<ScheduledReportActionState>;

function ActionForm({ action, submitLabel, loadingLabel, variant = "primary" }: { action: BoundFormAction; submitLabel: string; loadingLabel?: string; variant?: "primary" | "secondary" | "destructive" }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2">
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant={variant} loading={pending} loadingLabel={loadingLabel ?? "Working…"} className="w-fit">
        {submitLabel}
      </Button>
    </form>
  );
}

/**
 * ISS-2026-242: the one `ActionForm` caller that carried a real field is its own form
 * now -- a generic wrapper cannot wire `aria-describedby` from a field it only receives
 * as opaque `children` to the error text it renders itself. Same action, same submit
 * label/variant, same error text.
 */
function AddRecipientForm({ action }: { action: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "add-scheduled-report-recipient-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2">
      <FormField id="recipientAuthUserId" label="Recipient's auth user id (must be an active tenant member)">
        <Input
          id="recipientAuthUserId"
          name="recipientAuthUserId"
          placeholder="Recipient's auth user id (must be an active tenant member)"
          required
          className="font-mono"
          invalid={Boolean(state.error)}
          aria-describedby={describedBy}
        />
      </FormField>
      {state.error ? <ValidationMessage id="add-scheduled-report-recipient-error">{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add recipient
      </Button>
    </form>
  );
}

export function ScheduledReportDetailPanel({
  schedule,
  reportTypeName,
  recipients,
  runs,
  setStatusActionFor,
  addRecipientAction,
  removeRecipientActionFor,
  runNowAction,
}: {
  schedule: ScheduledReport;
  reportTypeName: string;
  recipients: readonly ScheduledReportRecipient[];
  runs: readonly ScheduledReportRun[];
  setStatusActionFor: (status: ScheduledReportStatus) => BoundFormAction;
  addRecipientAction: BoundFormAction;
  removeRecipientActionFor: (recipientRowId: string) => BoundFormAction;
  runNowAction: BoundFormAction;
}) {
  const recurrence = schedule.cronDayOfWeek !== null ? `weekly on day ${schedule.cronDayOfWeek}` : schedule.cronDayOfMonth !== null ? `monthly on day ${schedule.cronDayOfMonth}` : "daily";

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">{schedule.name}</h1>
        <StatusBadge tone={STATUS_TONE[schedule.status]} label={schedule.status} />
      </header>
      <p className="text-xs text-neutral-500">
        {reportTypeName} · {recurrence} at {String(schedule.cronHour).padStart(2, "0")}:{String(schedule.cronMinute).padStart(2, "0")} {schedule.timezone} · next run: {schedule.nextRunAt}
        {schedule.lastRunAt ? ` · last run: ${schedule.lastRunAt}` : ""}
      </p>
      {schedule.description ? <p className="text-xs text-neutral-500">{schedule.description}</p> : null}

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-neutral-900">Controls</h2>
        <div className="flex flex-wrap gap-3">
          <ActionForm action={runNowAction} submitLabel="Run now" loadingLabel="Running…" />
          {schedule.status === "active" ? <ActionForm action={setStatusActionFor("paused")} submitLabel="Pause" loadingLabel="Pausing…" variant="secondary" /> : null}
          {schedule.status === "paused" ? <ActionForm action={setStatusActionFor("active")} submitLabel="Resume" loadingLabel="Resuming…" variant="secondary" /> : null}
          {schedule.status !== "archived" ? <ActionForm action={setStatusActionFor("archived")} submitLabel="Archive" loadingLabel="Archiving…" variant="destructive" /> : null}
        </div>
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Recipients (internal tenant members only)</h2>
        {recipients.length === 0 ? (
          <EmptyState title="No recipients yet" description="Add one below." />
        ) : (
          <ul className="flex flex-col gap-2">
            {recipients.map((r) => (
              <li key={r.id} className="flex items-center justify-between rounded-md border border-neutral-100 p-2 text-sm">
                <span className="font-mono text-xs">{r.recipientAuthUserId}</span>
                <ActionForm action={removeRecipientActionFor(r.id)} submitLabel="Remove" loadingLabel="Removing…" variant="destructive" />
              </li>
            ))}
          </ul>
        )}
        <AddRecipientForm action={addRecipientAction} />
      </section>

      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Run history</h2>
        {runs.length === 0 ? (
          <EmptyState title="No runs yet" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[420px] text-sm">
              <thead>
                <tr className="text-left text-xs text-neutral-500">
                  <th className="pb-1">Started</th>
                  <th className="pb-1">Status</th>
                  <th className="pb-1">Recipients</th>
                </tr>
              </thead>
              <tbody>
                {runs.map((r) => (
                  <tr key={r.id} className="border-t border-neutral-100">
                    <td className="py-1">{r.startedAt}</td>
                    <td className="py-1">
                      <StatusBadge tone={RUN_STATUS_TONE[r.status]} label={r.status} />
                    </td>
                    <td className="py-1">
                      {r.recipientsReauthorized}/{r.recipientsTotal} reauthorized{r.recipientsDenied > 0 ? `, ${r.recipientsDenied} denied` : ""}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    </div>
  );
}
