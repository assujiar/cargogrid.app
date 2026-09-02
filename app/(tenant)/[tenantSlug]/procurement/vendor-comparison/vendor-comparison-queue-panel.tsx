"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { VENDOR_COMPARISON_STATUSES, type VendorComparison, type VendorComparisonStatus } from "../../../../../server/contracts/vendor-comparison/vendor-comparison.ts";
import type { VendorComparisonActionState } from "./actions.ts";

const INITIAL_STATE: VendorComparisonActionState = { error: null };

const STATUS_TONE: Record<VendorComparisonStatus, StatusTone> = {
  draft: "neutral",
  recommended: "info",
  submitted: "success",
  cancelled: "danger",
  superseded: "neutral",
};

type BoundFormAction = (prevState: VendorComparisonActionState, formData: FormData) => Promise<VendorComparisonActionState>;

export function VendorComparisonQueuePanel({
  tenantSlug,
  comparisons,
  statusFilter,
  createAction,
}: {
  tenantSlug: string;
  comparisons: readonly VendorComparison[];
  statusFilter: VendorComparisonStatus | null;
  createAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [createState, createFormAction, createPending] = useActionState(createAction, INITIAL_STATE);
  const createErrorId = "vendor-comparison-create-error";
  const createDescribedBy = createState.error ? createErrorId : undefined;

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/vendor-comparison?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <form action={createFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
          <FormField id="rfqId" label="Closed RFQ id (required)">
            <Input id="rfqId" name="rfqId" type="text" required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="comparisonCurrency" label="Comparison currency (required)">
            <Input id="comparisonCurrency" name="comparisonCurrency" type="text" maxLength={3} required invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="basisWeight" label="Basis weight (kg)">
            <Input id="basisWeight" name="basisWeight" type="number" min={0} invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="basisVolume" label="Basis volume (cbm)">
            <Input id="basisVolume" name="basisVolume" type="number" min={0} invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="basisQuantity" label="Basis quantity (units, needed to link a rate)">
            <Input id="basisQuantity" name="basisQuantity" type="number" min={0} invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <div className="sm:col-span-3">
            <FormField id="criteria" label="Criteria (JSON array, optional -- defaults to 100% price)">
              <Input id="criteria" name="criteria" type="text" placeholder='[{"key":"price","label":"Price","weight":70},{"key":"service","label":"Service","weight":30}]' invalid={Boolean(createState.error)} aria-describedby={createDescribedBy} />
            </FormField>
          </div>
        </div>
        {createState.error ? <ValidationMessage id={createErrorId}>{createState.error}</ValidationMessage> : null}
        <Button type="submit" loading={createPending} loadingLabel="Creating…" className="w-fit">
          Create comparison
        </Button>
      </form>

      <div className="flex items-center gap-2">
        <label htmlFor="comparison-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <Select
          id="comparison-status"
          defaultValue={statusFilter ?? ""}
          className="w-auto py-1.5"
          onChange={(event) => applyStatusFilter(event.currentTarget.value)}
        >
          <option value="">All (excludes superseded)</option>
          {VENDOR_COMPARISON_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
      </div>

      {comparisons.length === 0 ? (
        <EmptyState title="No vendor comparisons match this view" description="Create one above from a closed RFQ." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">Comparison</th>
                <th className="px-3 py-2">Currency</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Submitted</th>
              </tr>
            </thead>
            <tbody>
              {comparisons.map((comparison) => (
                <tr key={comparison.id} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/vendor-comparison/${comparison.id}`} className="font-medium text-primary hover:underline">
                      {comparison.id.slice(0, 8)}
                    </Link>
                    <span className="ml-1 text-xs text-neutral-500">v{comparison.version}</span>
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{comparison.comparisonCurrency}</td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[comparison.status]} label={comparison.status} />
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{comparison.submittedAt ? new Date(comparison.submittedAt).toLocaleString() : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
