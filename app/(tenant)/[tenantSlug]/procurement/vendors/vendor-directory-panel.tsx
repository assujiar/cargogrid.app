"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { VendorActionState } from "./actions.ts";
import { VENDOR_LIFECYCLE_STATUSES, type VendorLifecycleStatus, type VendorProfileListRow } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";

const INITIAL_STATE: VendorActionState = { error: null };

const STATUS_TONE: Record<VendorLifecycleStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  under_review: "info",
  approved: "info",
  active: "success",
  suspended: "warning",
  archived: "neutral",
  blacklisted: "danger",
};

export function VendorDirectoryPanel({
  tenantSlug,
  vendors,
  statusFilter,
  search,
  createAction,
}: {
  tenantSlug: string;
  vendors: readonly VendorProfileListRow[];
  statusFilter: VendorLifecycleStatus | null;
  search: string;
  createAction: (prevState: VendorActionState, formData: FormData) => Promise<VendorActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [state, formAction, pending] = useActionState(createAction, INITIAL_STATE);

  function applyFilter(nextStatus: string, nextSearch: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    if (nextSearch) next.set("q", nextSearch);
    else next.delete("q");
    next.delete("after");
    router.push(`/${tenantSlug}/procurement/vendors?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex flex-col gap-1">
            <label htmlFor="vendor-search" className="text-xs font-medium text-neutral-600">
              Search
            </label>
            <input
              id="vendor-search"
              type="search"
              defaultValue={search}
              placeholder="Legal name, trade name, or code"
              className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="vendor-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <select id="vendor-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {VENDOR_LIFECYCLE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>
        </div>

        {vendors.length === 0 ? (
          <EmptyState title="No vendors match this view" description="Adjust your search/status filter, or register a new vendor below." />
        ) : (
          <div className="overflow-x-auto">
          <table className="w-full min-w-[560px] text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Code</th>
                <th className="pb-1">Legal name</th>
                <th className="pb-1">Category</th>
                <th className="pb-1">Intake source</th>
                <th className="pb-1">Status</th>
              </tr>
            </thead>
            <tbody>
              {vendors.map((vendor) => (
                <tr key={vendor.masterRecordId} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/procurement/vendors/${vendor.masterRecordId}`} className="text-primary underline">
                      {vendor.vendorCode}
                    </Link>
                  </td>
                  <td className="py-1">
                    {vendor.legalName}
                    {vendor.tradeName ? <span className="text-neutral-500"> ({vendor.tradeName})</span> : null}
                  </td>
                  <td className="py-1">{vendor.vendorCategory ?? "—"}</td>
                  <td className="py-1 text-xs">{vendor.intakeSource.replace(/_/g, " ")}</td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[vendor.lifecycleStatus]} label={vendor.lifecycleStatus.replace(/_/g, " ")} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          </div>
        )}
      </section>

      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <h2 className="text-sm font-semibold text-neutral-900">Register a new vendor</h2>
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div className="flex flex-col gap-1">
            <label htmlFor="legalName" className="text-xs font-medium text-neutral-600">
              Legal name
            </label>
            <input id="legalName" name="legalName" type="text" required className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="tradeName" className="text-xs font-medium text-neutral-600">
              Trade name (optional)
            </label>
            <input id="tradeName" name="tradeName" type="text" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="legalEntityType" className="text-xs font-medium text-neutral-600">
              Legal entity type
            </label>
            <input id="legalEntityType" name="legalEntityType" type="text" placeholder="PT, CV, Perorangan, Foreign…" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="businessRegistrationNumber" className="text-xs font-medium text-neutral-600">
              Business registration number (optional)
            </label>
            <input id="businessRegistrationNumber" name="businessRegistrationNumber" type="text" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="vendorCategory" className="text-xs font-medium text-neutral-600">
              Category
            </label>
            <input id="vendorCategory" name="vendorCategory" type="text" placeholder="trucking, warehousing…" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="paymentTermDays" className="text-xs font-medium text-neutral-600">
              Payment term (days, optional)
            </label>
            <input id="paymentTermDays" name="paymentTermDays" type="number" min="0" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" />
          </div>

          {state.error ? (
            <p role="alert" className="col-span-full text-sm text-danger">
              {state.error}
            </p>
          ) : null}

          <div className="col-span-full">
            <Button type="submit" loading={pending} loadingLabel="Creating…">
              Create draft
            </Button>
          </div>
        </form>
      </section>
    </div>
  );
}
