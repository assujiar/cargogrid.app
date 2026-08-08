"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { VENDOR_CAPACITY_OFFER_STATUSES, type VendorCapacityOffer, type VendorCapacityOfferStatus } from "../../../../../server/contracts/vendor-capacity/vendor-capacity.ts";
import type { VendorProfileListRow } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";
import type { VendorCapacityActionState } from "./actions.ts";

const INITIAL_STATE: VendorCapacityActionState = { error: null };

const STATUS_TONE: Record<VendorCapacityOfferStatus, StatusTone> = {
  draft: "neutral",
  published: "success",
  archived: "neutral",
};

type BoundFormAction = (prevState: VendorCapacityActionState, formData: FormData) => Promise<VendorCapacityActionState>;

export function VendorCapacityQueuePanel({
  tenantSlug,
  offers,
  activeVendors,
  statusFilter,
  createAction,
}: {
  tenantSlug: string;
  offers: readonly VendorCapacityOffer[];
  activeVendors: readonly VendorProfileListRow[];
  statusFilter: VendorCapacityOfferStatus | null;
  createAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [createState, createFormAction, createPending] = useActionState(createAction, INITIAL_STATE);

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/vendor-capacity?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <form action={createFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
          <div className="flex flex-col gap-1 sm:col-span-2">
            <label htmlFor="vendorMasterId" className="text-xs font-medium text-neutral-700">
              Vendor (required, active only)
            </label>
            <select id="vendorMasterId" name="vendorMasterId" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              <option value="">Select a vendor…</option>
              {activeVendors.map((v) => (
                <option key={v.masterRecordId} value={v.masterRecordId}>
                  {v.legalName} ({v.vendorCode})
                </option>
              ))}
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="serviceType" className="text-xs font-medium text-neutral-700">
              Service type (required)
            </label>
            <Input id="serviceType" name="serviceType" type="text" required placeholder="ocean_freight" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="quantity" className="text-xs font-medium text-neutral-700">
              Quantity (required)
            </label>
            <Input id="quantity" name="quantity" type="number" min={0.001} step="any" required />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="uom" className="text-xs font-medium text-neutral-700">
              UOM (required)
            </label>
            <Input id="uom" name="uom" type="text" required placeholder="teu" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="windowStart" className="text-xs font-medium text-neutral-700">
              Window start (required)
            </label>
            <Input id="windowStart" name="windowStart" type="date" required />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="windowEnd" className="text-xs font-medium text-neutral-700">
              Window end (required)
            </label>
            <Input id="windowEnd" name="windowEnd" type="date" required />
          </div>
        </div>
        {createState.error ? (
          <p role="alert" className="text-sm text-danger">
            {createState.error}
          </p>
        ) : null}
        <Button type="submit" loading={createPending} loadingLabel="Creating…" className="w-fit">
          Create draft offer
        </Button>
      </form>

      <div className="flex items-center gap-2">
        <label htmlFor="vcap-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <select id="vcap-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyStatusFilter(event.currentTarget.value)}>
          <option value="">All</option>
          {VENDOR_CAPACITY_OFFER_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </div>

      {offers.length === 0 ? (
        <EmptyState title="No vendor capacity offers match this view" description="Create one above for an active vendor." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">Service</th>
                <th className="px-3 py-2">Lane</th>
                <th className="px-3 py-2">Quantity</th>
                <th className="px-3 py-2">Window</th>
                <th className="px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {offers.map((o) => (
                <tr key={o.id} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/vendor-capacity/${o.id}`} className="font-medium text-primary hover:underline">
                      {o.serviceType}
                    </Link>
                    {o.mode ? <span className="ml-1 text-xs text-neutral-500">({o.mode})</span> : null}
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {o.originLane ?? "—"} → {o.destinationLane ?? "—"}
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {o.quantity.toLocaleString()} {o.uom}
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {new Date(o.windowStart).toLocaleDateString()} → {new Date(o.windowEnd).toLocaleDateString()}
                  </td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[o.status]} label={o.status} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
