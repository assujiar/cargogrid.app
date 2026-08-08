"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { PROCUREMENT_DASHBOARD_METRIC_GROUPS, type ProcurementDashboardSavedView } from "../../../../../server/contracts/procurement-dashboard/procurement-dashboard.ts";
import type { ProcurementDashboardActionState } from "./actions.ts";

const INITIAL_STATE: ProcurementDashboardActionState = { error: null };

type BoundFormAction = (prevState: ProcurementDashboardActionState, formData: FormData) => Promise<ProcurementDashboardActionState>;

const GROUP_LABEL: Record<(typeof PROCUREMENT_DASHBOARD_METRIC_GROUPS)[number], string> = {
  vendor_risk_compliance: "Vendor risk / compliance",
  rate_validity_competitiveness: "Rate validity / competitiveness",
  rfq_response_cycle: "RFQ response / cycle time",
  capacity_acceptance: "Capacity / acceptance",
  po_contract: "PO / contract",
  performance: "Performance",
  match_variance_exception: "Match variance / exception",
};

function DeleteSavedViewForm({ view, deleteAction }: { view: ProcurementDashboardSavedView; deleteAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(deleteAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col items-end gap-1">
      <input type="hidden" name="viewId" value={view.id} />
      <input type="hidden" name="expectedVersion" value={view.recordVersion} />
      <Button type="submit" variant="destructive" loading={pending} loadingLabel="Removing…" className="shrink-0 text-xs">
        Remove
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

export function SavedViewsPanel({
  tenantSlug,
  views,
  createAction,
  deleteAction,
}: {
  tenantSlug: string;
  views: readonly ProcurementDashboardSavedView[];
  createAction: BoundFormAction;
  deleteAction: BoundFormAction;
}) {
  const [createState, createFormAction, createPending] = useActionState(createAction, INITIAL_STATE);

  return (
    <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Your saved views</h2>
      <p className="text-xs text-neutral-500">A named shortcut back to one dashboard section. Owner-private -- no one else on this tenant sees your own saved views.</p>

      {views.length === 0 ? (
        <EmptyState title="No saved views yet" description="Save a shortcut to a dashboard section below." />
      ) : (
        <ul className="flex flex-col gap-2">
          {views.map((view) => (
            <li key={view.id} className="flex items-center justify-between gap-2 rounded-md border border-neutral-200 p-2">
              <div>
                <p className="text-sm font-medium text-neutral-900">{view.name}</p>
                <p className="text-xs text-neutral-500">{GROUP_LABEL[view.metricGroup]}</p>
                {view.description ? <p className="text-xs text-neutral-500">{view.description}</p> : null}
              </div>
              <DeleteSavedViewForm view={view} deleteAction={deleteAction} />
            </li>
          ))}
        </ul>
      )}

      <form action={createFormAction} className="mt-2 flex flex-col gap-2 border-t border-neutral-200 pt-3 sm:flex-row sm:items-end" noValidate>
        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor={`sv-name-${tenantSlug}`} className="text-xs font-medium text-neutral-700">
            Name (required)
          </label>
          <Input id={`sv-name-${tenantSlug}`} name="name" required />
        </div>
        <div className="flex flex-1 flex-col gap-1">
          <label htmlFor={`sv-group-${tenantSlug}`} className="text-xs font-medium text-neutral-700">
            Section
          </label>
          <select id={`sv-group-${tenantSlug}`} name="metricGroup" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
            {PROCUREMENT_DASHBOARD_METRIC_GROUPS.map((g) => (
              <option key={g} value={g}>
                {GROUP_LABEL[g]}
              </option>
            ))}
          </select>
        </div>
        <Button type="submit" loading={createPending} loadingLabel="Saving…" className="shrink-0">
          Save view
        </Button>
      </form>
      {createState.error ? (
        <p role="alert" className="text-sm text-danger">
          {createState.error}
        </p>
      ) : null}
    </section>
  );
}
