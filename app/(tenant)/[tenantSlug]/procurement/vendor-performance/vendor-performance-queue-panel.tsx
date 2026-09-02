"use client";

import { useActionState } from "react";
import Link from "next/link";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { VendorProfileListRow } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";
import { VENDOR_KPI_CODES, VENDOR_KPI_TARGET_OPERATORS, VENDOR_KPI_UNITS, type VendorKpiBand, type VendorKpiDefinition, type VendorKpiScorecard } from "../../../../../server/contracts/vendor-performance/vendor-performance.ts";
import type { VendorPerformanceActionState } from "./actions.ts";

const INITIAL_STATE: VendorPerformanceActionState = { error: null };

const BAND_TONE: Record<VendorKpiBand, StatusTone> = {
  excellent: "success",
  good: "success",
  watch: "warning",
  poor: "danger",
};

type BoundFormAction = (prevState: VendorPerformanceActionState, formData: FormData) => Promise<VendorPerformanceActionState>;

function ArchiveDefinitionForm({ definition, archiveDefinitionAction }: { definition: VendorKpiDefinition; archiveDefinitionAction: BoundFormAction }) {
  const [state, formAction, pending] = useActionState(archiveDefinitionAction, INITIAL_STATE);
  const errorId = `archive-def-${definition.id}-error`;
  const describedBy = state.error ? errorId : undefined;
  return (
    <form action={formAction} className="mt-1 flex flex-col gap-1">
      <input type="hidden" name="definitionId" value={definition.id} />
      <input type="hidden" name="expectedVersion" value={definition.recordVersion} />
      <div className="flex items-center gap-1">
        <label htmlFor={`archive-def-reason-${definition.id}`} className="sr-only">
          Archive reason
        </label>
        <Input id={`archive-def-reason-${definition.id}`} name="reason" placeholder="Archive reason (required)" required className="w-40 text-xs" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        <Button type="submit" variant="destructive" loading={pending} loadingLabel="Archiving…" className="shrink-0 text-xs">
          Archive
        </Button>
      </div>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
    </form>
  );
}

export function VendorPerformanceQueuePanel({
  tenantSlug,
  vendors,
  scorecards,
  definitions,
  createDefinitionAction,
  publishDefinitionAction,
  archiveDefinitionAction,
}: {
  tenantSlug: string;
  vendors: readonly VendorProfileListRow[];
  scorecards: readonly VendorKpiScorecard[];
  definitions: readonly VendorKpiDefinition[];
  createDefinitionAction: BoundFormAction;
  publishDefinitionAction: BoundFormAction;
  archiveDefinitionAction: BoundFormAction;
}) {
  const [createState, createFormAction, createPending] = useActionState(createDefinitionAction, INITIAL_STATE);
  const [publishState, publishFormAction, publishPending] = useActionState(publishDefinitionAction, INITIAL_STATE);
  const createErrorId = "kpi-create-error";
  const createDescribedBy = createState.error ? createErrorId : undefined;

  const scorecardByVendor = new Map(scorecards.map((s) => [s.vendorMasterId, s]));

  return (
    <div className="flex flex-col gap-6">
      <section className="flex flex-col gap-2">
        <h2 className="text-sm font-semibold text-neutral-900">Vendors</h2>
        {vendors.length === 0 ? (
          <EmptyState title="No active vendors" description="Activate a vendor profile first." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Vendor</th>
                  <th className="px-3 py-2">Band</th>
                  <th className="px-3 py-2">Composite score</th>
                  <th className="px-3 py-2">Coverage</th>
                  <th className="px-3 py-2">Window</th>
                </tr>
              </thead>
              <tbody>
                {vendors.map((v) => {
                  const card = scorecardByVendor.get(v.masterRecordId);
                  return (
                    <tr key={v.masterRecordId} className="border-t border-neutral-200">
                      <td className="px-3 py-2">
                        <Link href={`/${tenantSlug}/procurement/vendor-performance/${v.masterRecordId}`} className="font-medium text-primary hover:underline">
                          {v.legalName}
                        </Link>
                        <span className="ml-1 text-xs text-neutral-500">({v.vendorCode})</span>
                      </td>
                      <td className="px-3 py-2">{card?.band ? <StatusBadge tone={BAND_TONE[card.band]} label={card.band} /> : <span className="text-xs text-neutral-400">no scorecard yet</span>}</td>
                      <td className="px-3 py-2 text-neutral-700">{card?.compositeScore != null ? card.compositeScore.toFixed(1) : "—"}</td>
                      <td className="px-3 py-2 text-xs text-neutral-500">{card ? `${card.computableWeightTotal} of ${card.totalWeightDefined} weight` : "—"}</td>
                      <td className="px-3 py-2 text-xs text-neutral-500">{card ? `${new Date(card.windowStart).toLocaleDateString()} – ${new Date(card.windowEnd).toLocaleDateString()}` : "—"}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">KPI Catalogue</h2>
        <p className="text-xs text-neutral-500">Versioned formula/window/target/weight/band per category (app.vendor_kpi_definitions). At most one published version per category at a time.</p>

        {definitions.length === 0 ? (
          <EmptyState title="No KPI categories configured yet" description="Create and publish at least one below before calculating any vendor's metrics." />
        ) : (
          <div className="overflow-x-auto rounded-md border border-neutral-200">
            <table className="w-full text-sm">
              <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
                <tr>
                  <th className="px-3 py-2">Category</th>
                  <th className="px-3 py-2">Status</th>
                  <th className="px-3 py-2">Target</th>
                  <th className="px-3 py-2">Weight</th>
                  <th className="px-3 py-2">Computable</th>
                  <th className="px-3 py-2" />
                </tr>
              </thead>
              <tbody>
                {definitions.map((d) => (
                  <tr key={d.id} className="border-t border-neutral-200">
                    <td className="px-3 py-2 font-medium text-neutral-900">
                      {d.kpiCode} <span className="text-xs text-neutral-500">v{d.versionNo}</span>
                    </td>
                    <td className="px-3 py-2">
                      <StatusBadge tone={d.status === "published" ? "success" : d.status === "draft" ? "neutral" : "neutral"} label={d.status} />
                    </td>
                    <td className="px-3 py-2 text-neutral-700">
                      {d.targetOperator} {d.targetValue} {d.unit}
                    </td>
                    <td className="px-3 py-2 text-neutral-700">{d.weight}</td>
                    <td className="px-3 py-2 text-neutral-700">{d.isComputable ? "yes" : `no — ${d.sourceNote ?? "not disclosed"}`}</td>
                    <td className="px-3 py-2">
                      {d.status === "draft" ? (
                        <form action={publishFormAction} className="inline">
                          <input type="hidden" name="definitionId" value={d.id} />
                          <input type="hidden" name="expectedVersion" value={d.recordVersion} />
                          <Button type="submit" variant="secondary" loading={publishPending} loadingLabel="Publishing…">
                            Publish
                          </Button>
                        </form>
                      ) : null}
                      {d.status === "draft" || d.status === "published" ? <ArchiveDefinitionForm definition={d} archiveDefinitionAction={archiveDefinitionAction} /> : null}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        {publishState.error ? <ValidationMessage>{publishState.error}</ValidationMessage> : null}

        <form action={createFormAction} className="mt-2 flex flex-col gap-2 border-t border-neutral-200 pt-3" noValidate>
          <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
            <FormField id="kpiCode" label="Category (required)">
              <Select id="kpiCode" name="kpiCode" required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy}>
                {VENDOR_KPI_CODES.map((c) => (
                  <option key={c} value={c}>
                    {c}
                  </option>
                ))}
              </Select>
            </FormField>
            <FormField id="name" label="Name (required)">
              <Input id="name" name="name" required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
            </FormField>
            <FormField id="measurementWindowDays" label="Window (days)">
              <Input id="measurementWindowDays" name="measurementWindowDays" type="number" min={1} defaultValue={30} required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
            </FormField>
            <FormField id="minSampleSize" label="Min sample size">
              <Input id="minSampleSize" name="minSampleSize" type="number" min={0} defaultValue={1} invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
            </FormField>
            <FormField id="targetValue" label="Target value (required)">
              <Input id="targetValue" name="targetValue" type="number" step="any" required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
            </FormField>
            <FormField id="targetOperator" label="Target operator">
              <Select id="targetOperator" name="targetOperator" invalid={Boolean(createState.error)} aria-describedby={createDescribedBy}>
                {VENDOR_KPI_TARGET_OPERATORS.map((o) => (
                  <option key={o} value={o}>
                    {o === "gte" ? "higher is better (gte)" : "lower is better (lte)"}
                  </option>
                ))}
              </Select>
            </FormField>
            <FormField id="weight" label="Weight (required, 0–100)">
              <Input id="weight" name="weight" type="number" min={0.01} max={100} step="any" required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
            </FormField>
            <FormField id="unit" label="Unit">
              <Select id="unit" name="unit" invalid={Boolean(createState.error)} aria-describedby={createDescribedBy}>
                {VENDOR_KPI_UNITS.map((u) => (
                  <option key={u} value={u}>
                    {u}
                  </option>
                ))}
              </Select>
            </FormField>
          </div>
          <div className="flex flex-col gap-1">
            <Checkbox id="notComputable" name="notComputable" label="This category is not yet sourced (e.g. invoice accuracy pending Prompt 265) — requires a source note below" aria-describedby={createDescribedBy} />
            <FormField id="sourceNote" label={<span className="sr-only">Source note</span>}>
              <Input id="sourceNote" name="sourceNote" placeholder="Required only when not-yet-sourced is checked" invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
            </FormField>
          </div>
          {createState.error ? <ValidationMessage id={createErrorId}>{createState.error}</ValidationMessage> : null}
          <Button type="submit" loading={createPending} loadingLabel="Creating…" className="w-fit">
            Create draft KPI definition
          </Button>
        </form>
      </section>
    </div>
  );
}
