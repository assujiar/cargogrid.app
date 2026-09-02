"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { TenantDashboardActionState } from "../actions.ts";
import type { TenantDashboard, TenantDashboardVersion, TenantDashboardWidget, TenantDashboardStatus } from "../../../../../server/contracts/tenant-dashboard/tenant-dashboard.ts";
import type { ReportType } from "../../../../../server/contracts/report/report.ts";

const INITIAL_STATE: TenantDashboardActionState = { error: null };

const STATUS_TONE: Record<TenantDashboardStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

type BoundFormAction = (prevState: TenantDashboardActionState, formData: FormData) => Promise<TenantDashboardActionState>;

function ActionForm({
  action,
  submitLabel,
  loadingLabel,
  variant = "primary",
}: {
  action: BoundFormAction;
  submitLabel: string;
  loadingLabel?: string;
  variant?: "primary" | "secondary" | "destructive";
}) {
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
 * ISS-2026-242: the one `ActionForm` caller that carried real fields is its own
 * form now -- a generic wrapper cannot wire `aria-describedby` from a field it
 * only receives as opaque `children` to the error text it renders itself.
 * Same action, same submit label/variant, same error text; the two controls
 * simply gain a programmatic label and an error association.
 */
function AddWidgetForm({ action, reportTypes }: { action: BoundFormAction; reportTypes: readonly ReportType[] }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "add-widget-error" : undefined;
  return (
    <form action={formAction} className="flex flex-col gap-2">
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
        <div className="sm:col-span-2">
          <FormField id="add-widget-report-type" label="Report">
            <Select id="add-widget-report-type" name="reportTypeCode" required invalid={Boolean(state.error)} aria-describedby={describedBy}>
              <option value="">Select a report…</option>
              {reportTypes.map((t) => (
                <option key={t.code} value={t.code}>
                  {t.name}
                </option>
              ))}
            </Select>
          </FormField>
        </div>
        <FormField id="add-widget-title" label="Widget title">
          <Input id="add-widget-title" name="title" placeholder="Widget title" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
      </div>
      {state.error ? <ValidationMessage id="add-widget-error">{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…" className="w-fit">
        Add widget
      </Button>
    </form>
  );
}

function WidgetList({ widgets, removeActionFor }: { widgets: readonly TenantDashboardWidget[]; removeActionFor?: (widgetId: string) => BoundFormAction }) {
  if (widgets.length === 0) {
    return <EmptyState title="No widgets yet" description={removeActionFor ? "Add one below." : undefined} />;
  }
  return (
    <ul className="flex flex-col gap-2">
      {widgets.map((w) => (
        <li key={w.id} className="flex items-center justify-between rounded-md border border-neutral-100 p-2 text-sm">
          <div>
            <p className="font-medium text-neutral-900">{w.title}</p>
            <p className="text-xs text-neutral-500">{w.reportTypeCode}</p>
          </div>
          {removeActionFor ? <ActionForm action={removeActionFor(w.id)} submitLabel="Remove" loadingLabel="Removing…" variant="destructive" /> : null}
        </li>
      ))}
    </ul>
  );
}

export function DashboardDetailPanel({
  dashboard,
  versions,
  draftVersion,
  draftWidgets,
  publishedWidgets,
  reportTypes,
  addWidgetAction,
  removeWidgetActionFor,
  publishAction,
  rollbackActionFor,
}: {
  dashboard: TenantDashboard;
  versions: readonly TenantDashboardVersion[];
  draftVersion: TenantDashboardVersion | null;
  draftWidgets: readonly TenantDashboardWidget[];
  publishedWidgets: readonly TenantDashboardWidget[];
  reportTypes: readonly ReportType[];
  addWidgetAction: BoundFormAction | null;
  removeWidgetActionFor: (widgetId: string) => BoundFormAction;
  publishAction: BoundFormAction;
  rollbackActionFor: (targetVersionId: string) => BoundFormAction;
}) {
  const otherPublishedVersions = versions.filter((v) => v.status === "published" && v.id !== dashboard.currentVersionId);

  return (
    <div className="flex flex-col gap-6">
      <header className="flex flex-wrap items-center gap-2">
        <h1 className="text-xl font-semibold text-neutral-900">{dashboard.name}</h1>
        <StatusBadge tone={STATUS_TONE[dashboard.status]} label={dashboard.status} />
      </header>
      {dashboard.description ? <p className="text-xs text-neutral-500">{dashboard.description}</p> : null}

      {dashboard.status === "published" ? (
        <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
          <h2 className="text-sm font-semibold text-neutral-900">Published widgets</h2>
          <WidgetList widgets={publishedWidgets} />
        </section>
      ) : null}

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Draft widgets</h2>
        <WidgetList widgets={draftWidgets} removeActionFor={removeWidgetActionFor} />

        {addWidgetAction ? <AddWidgetForm action={addWidgetAction} reportTypes={reportTypes} /> : null}
      </section>

      <section className="rounded-md border border-neutral-200 p-4">
        <h2 className="mb-2 text-sm font-semibold text-neutral-900">Publish</h2>
        <p className="mb-2 text-xs text-neutral-500">Publishing the current draft opens a new draft version copying these same widgets, so editing can continue without ever mutating a published snapshot.</p>
        <ActionForm action={publishAction} submitLabel="Publish draft" loadingLabel="Publishing…" />
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Version history</h2>
        {versions.length === 0 ? (
          <EmptyState title="No versions yet" />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[480px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Version</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Published</th>
                <th className="pb-1" />
              </tr>
            </thead>
            <tbody>
              {versions.map((v) => (
                <tr key={v.id} className="border-t border-neutral-100">
                  <td className="py-1">v{v.versionNumber}</td>
                  <td className="py-1">
                    <StatusBadge tone={v.id === dashboard.currentVersionId ? "success" : "neutral"} label={v.id === dashboard.currentVersionId ? "current" : v.status} />
                  </td>
                  <td className="py-1">{v.publishedAt ?? "—"}</td>
                  <td className="py-1">
                    {otherPublishedVersions.some((ov) => ov.id === v.id) ? <ActionForm action={rollbackActionFor(v.id)} submitLabel="Roll back" loadingLabel="Rolling back…" variant="secondary" /> : null}
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
