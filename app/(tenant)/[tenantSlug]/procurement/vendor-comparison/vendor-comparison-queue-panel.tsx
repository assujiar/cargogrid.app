"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
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
          <div className="flex flex-col gap-1">
            <label htmlFor="rfqId" className="text-xs font-medium text-neutral-700">
              Closed RFQ id (required)
            </label>
            <Input id="rfqId" name="rfqId" type="text" required />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="comparisonCurrency" className="text-xs font-medium text-neutral-700">
              Comparison currency (required)
            </label>
            <Input id="comparisonCurrency" name="comparisonCurrency" type="text" maxLength={3} required />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="basisWeight" className="text-xs font-medium text-neutral-700">
              Basis weight (kg)
            </label>
            <Input id="basisWeight" name="basisWeight" type="number" min={0} />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="basisVolume" className="text-xs font-medium text-neutral-700">
              Basis volume (cbm)
            </label>
            <Input id="basisVolume" name="basisVolume" type="number" min={0} />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="basisQuantity" className="text-xs font-medium text-neutral-700">
              Basis quantity (units, needed to link a rate)
            </label>
            <Input id="basisQuantity" name="basisQuantity" type="number" min={0} />
          </div>
          <div className="flex flex-col gap-1 sm:col-span-3">
            <label htmlFor="criteria" className="text-xs font-medium text-neutral-700">
              Criteria (JSON array, optional -- defaults to 100% price)
            </label>
            <Input id="criteria" name="criteria" type="text" placeholder='[{"key":"price","label":"Price","weight":70},{"key":"service","label":"Service","weight":30}]' />
          </div>
        </div>
        {createState.error ? (
          <p role="alert" className="text-sm text-danger">
            {createState.error}
          </p>
        ) : null}
        <Button type="submit" loading={createPending} loadingLabel="Creating…" className="w-fit">
          Create comparison
        </Button>
      </form>

      <div className="flex items-center gap-2">
        <label htmlFor="comparison-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <select
          id="comparison-status"
          defaultValue={statusFilter ?? ""}
          className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
          onChange={(event) => applyStatusFilter(event.currentTarget.value)}
        >
          <option value="">All (excludes superseded)</option>
          {VENDOR_COMPARISON_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
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
