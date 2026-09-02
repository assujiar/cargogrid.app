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
  const createErrorId = "vendor-create-error";
  const createDescribedBy = state.error ? createErrorId : undefined;

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
            <Input
              id="vendor-search"
              type="search"
              defaultValue={search}
              placeholder="Legal name, trade name, or code"
              className="py-1.5"
              onKeyDown={(event) => {
                if (event.key === "Enter") applyFilter(statusFilter ?? "", event.currentTarget.value);
              }}
            />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="vendor-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <Select id="vendor-status" defaultValue={statusFilter ?? ""} className="w-auto py-1.5" onChange={(event) => applyFilter(event.currentTarget.value, search)}>
              <option value="">All statuses</option>
              {VENDOR_LIFECYCLE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </Select>
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
        <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2" noValidate>
          <FormField id="legalName" label="Legal name">
            <Input id="legalName" name="legalName" type="text" required invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="tradeName" label="Trade name (optional)">
            <Input id="tradeName" name="tradeName" type="text" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="legalEntityType" label="Legal entity type">
            <Input id="legalEntityType" name="legalEntityType" type="text" placeholder="PT, CV, Perorangan, Foreign…" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="businessRegistrationNumber" label="Business registration number (optional)">
            <Input id="businessRegistrationNumber" name="businessRegistrationNumber" type="text" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="vendorCategory" label="Category">
            <Input id="vendorCategory" name="vendorCategory" type="text" placeholder="trucking, warehousing…" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>
          <FormField id="paymentTermDays" label="Payment term (days, optional)">
            <Input id="paymentTermDays" name="paymentTermDays" type="number" min="0" invalid={Boolean(state.error)} aria-describedby={createDescribedBy} />
          </FormField>

          {state.error ? (
            <div className="col-span-full">
              <ValidationMessage id={createErrorId}>{state.error}</ValidationMessage>
            </div>
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
