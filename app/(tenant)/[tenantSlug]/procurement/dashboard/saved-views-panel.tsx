"use client";

import { useActionState, useMemo, useState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { PROCUREMENT_DASHBOARD_METRIC_GROUPS, type ProcurementDashboardMetricGroup, type ProcurementDashboardSavedView } from "../../../../../server/contracts/procurement-dashboard/procurement-dashboard.ts";
import type { VendorRiskQueueFilters } from "./vendor-risk-queue-panel.tsx";
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
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function SavedViewsPanel({
  tenantSlug,
  views,
  vendorRiskFilters,
  createAction,
  deleteAction,
}: {
  tenantSlug: string;
  views: readonly ProcurementDashboardSavedView[];
  /**
   * The dashboard page's own CURRENTLY-APPLIED vendor risk/compliance-expiry filter
   * state (URL-driven, see vendor-risk-queue-panel.tsx). Tier C batch-5 fix
   * (spec-compliance, HIGH): before this fix, every saved view hardcoded
   * `filters: {}` regardless of section, because no filter UI existed anywhere on this
   * page to derive real values from -- a saved view could never actually capture a
   * filter/sort configuration, defeating its own stated purpose (migration design note
   * 5: "a user's own named filter/sort configuration"). Only the vendor risk/
   * compliance-expiry group has real filter UI today (the RPC-level filters for the
   * other six groups -- window_start/window_end, p_as_of -- have no UI control yet
   * either, a smaller, disclosed residual gap); saving a view for any OTHER
   * metric_group still saves an empty `filters: {}`, which is honest (there is
   * genuinely nothing to capture there yet), not silently wrong.
   */
  vendorRiskFilters: VendorRiskQueueFilters;
  createAction: BoundFormAction;
  deleteAction: BoundFormAction;
}) {
  const [createState, createFormAction, createPending] = useActionState(createAction, INITIAL_STATE);
  const [metricGroup, setMetricGroup] = useState<ProcurementDashboardMetricGroup>("vendor_risk_compliance");
  const createErrorId = `sv-create-error-${tenantSlug}`;
  const createDescribedBy = createState.error ? createErrorId : undefined;

  const filtersToSave = useMemo(() => {
    if (metricGroup !== "vendor_risk_compliance") return {};
    const captured: Record<string, string | boolean> = {};
    if (vendorRiskFilters.status) captured.lifecycleStatus = vendorRiskFilters.status;
    if (vendorRiskFilters.band) captured.band = vendorRiskFilters.band;
    if (vendorRiskFilters.hold) captured.complianceHoldOnly = true;
    if (vendorRiskFilters.search) captured.search = vendorRiskFilters.search;
    return captured;
  }, [metricGroup, vendorRiskFilters]);

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
                {Object.keys(view.filters).length > 0 ? (
                  <p className="text-xs text-neutral-400">
                    Filters:{" "}
                    {Object.entries(view.filters)
                      .map(([key, value]) => `${key}=${String(value)}`)
                      .join(", ")}
                  </p>
                ) : null}
              </div>
              <DeleteSavedViewForm view={view} deleteAction={deleteAction} />
            </li>
          ))}
        </ul>
      )}

      <form action={createFormAction} className="mt-2 flex flex-col gap-2 border-t border-neutral-200 pt-3 sm:flex-row sm:items-end" noValidate>
        <div className="flex-1">
          <FormField id={`sv-name-${tenantSlug}`} label="Name (required)">
            <Input id={`sv-name-${tenantSlug}`} name="name" required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
          </FormField>
        </div>
        <div className="flex-1">
          <FormField id={`sv-group-${tenantSlug}`} label="Section">
            <Select
              id={`sv-group-${tenantSlug}`}
              name="metricGroup"
              required
              value={metricGroup}
              onChange={(event) => setMetricGroup(event.currentTarget.value as ProcurementDashboardMetricGroup)}
              invalid={Boolean(createState.error)}
              aria-describedby={createDescribedBy}
            >
              {PROCUREMENT_DASHBOARD_METRIC_GROUPS.map((g) => (
                <option key={g} value={g}>
                  {GROUP_LABEL[g]}
                </option>
              ))}
            </Select>
          </FormField>
        </div>
        {/* Tier C batch-5 fix: the filters actually applied to the vendor risk/
            compliance-expiry queue right now, captured only when that section is the
            one being saved -- see this component's own vendorRiskFilters prop doc. */}
        <input type="hidden" name="filters" value={JSON.stringify(filtersToSave)} />
        {metricGroup === "vendor_risk_compliance" && Object.keys(filtersToSave).length > 0 ? (
          <p className="basis-full text-xs text-neutral-500">
            Will save with the filters currently applied above:{" "}
            {Object.entries(filtersToSave)
              .map(([key, value]) => `${key}=${String(value)}`)
              .join(", ")}
          </p>
        ) : null}
        <Button type="submit" loading={createPending} loadingLabel="Saving…" className="shrink-0">
          Save view
        </Button>
      </form>
      {createState.error ? <ValidationMessage id={createErrorId}>{createState.error}</ValidationMessage> : null}
    </section>
  );
}
