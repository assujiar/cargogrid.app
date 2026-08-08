"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { VENDOR_CONTRACT_STATUSES, type VendorContract, type VendorContractStatus } from "../../../../../server/contracts/vendor-contract/vendor-contract.ts";
import type { VendorProfileListRow } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";
import type { VendorContractActionState } from "./actions.ts";

const INITIAL_STATE: VendorContractActionState = { error: null };

const STATUS_TONE: Record<VendorContractStatus, StatusTone> = {
  draft: "neutral",
  pending_approval: "info",
  active: "success",
  rejected: "danger",
  suspended: "danger",
  terminated: "danger",
  superseded: "neutral",
  cancelled: "neutral",
};

type BoundFormAction = (prevState: VendorContractActionState, formData: FormData) => Promise<VendorContractActionState>;

export function VendorContractQueuePanel({
  tenantSlug,
  contracts,
  activeVendors,
  expiringSoon,
  statusFilter,
  createAction,
}: {
  tenantSlug: string;
  contracts: readonly VendorContract[];
  activeVendors: readonly VendorProfileListRow[];
  expiringSoon: readonly VendorContract[];
  statusFilter: VendorContractStatus | null;
  createAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [createState, createFormAction, createPending] = useActionState(createAction, INITIAL_STATE);

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/vendor-contracts?${next.toString()}`);
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
            <label htmlFor="contractType" className="text-xs font-medium text-neutral-700">
              Contract type
            </label>
            <select id="contractType" name="contractType" defaultValue="fixed_term" className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm">
              <option value="fixed_term">Fixed term</option>
              <option value="framework">Framework (open-ended)</option>
            </select>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="effectiveStart" className="text-xs font-medium text-neutral-700">
              Effective start (required)
            </label>
            <Input id="effectiveStart" name="effectiveStart" type="date" required />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="effectiveEnd" className="text-xs font-medium text-neutral-700">
              Effective end (required for fixed term)
            </label>
            <Input id="effectiveEnd" name="effectiveEnd" type="date" />
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="paymentTermDays" className="text-xs font-medium text-neutral-700">
              Payment term days
            </label>
            <Input id="paymentTermDays" name="paymentTermDays" type="number" min={0} />
          </div>
        </div>
        {createState.error ? (
          <p role="alert" className="text-sm text-danger">
            {createState.error}
          </p>
        ) : null}
        <Button type="submit" loading={createPending} loadingLabel="Creating…" className="w-fit">
          Create draft contract
        </Button>
      </form>

      {expiringSoon.length > 0 ? (
        <div className="rounded-md border border-warning/40 bg-warning/5 p-3">
          <h2 className="text-sm font-semibold text-neutral-900">Expiring within 30 days ({expiringSoon.length})</h2>
          <ul className="mt-1 flex flex-col gap-1 text-xs text-neutral-700">
            {expiringSoon.map((c) => (
              <li key={c.id}>
                <Link href={`/${tenantSlug}/procurement/vendor-contracts/${c.id}`} className="font-medium text-primary hover:underline">
                  {c.contractNumber}
                </Link>{" "}
                — effective end {c.effectiveEnd}
              </li>
            ))}
          </ul>
        </div>
      ) : null}

      <div className="flex items-center gap-2">
        <label htmlFor="vc-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <select id="vc-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyStatusFilter(event.currentTarget.value)}>
          <option value="">All</option>
          {VENDOR_CONTRACT_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </select>
      </div>

      {contracts.length === 0 ? (
        <EmptyState title="No vendor contracts match this view" description="Create one above for an active vendor." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">Contract number</th>
                <th className="px-3 py-2">Type</th>
                <th className="px-3 py-2">Effective</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Approval</th>
                <th className="px-3 py-2">Signature</th>
              </tr>
            </thead>
            <tbody>
              {contracts.map((c) => (
                <tr key={c.id} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/vendor-contracts/${c.id}`} className="font-medium text-primary hover:underline">
                      {c.contractNumber}
                    </Link>
                    <span className="ml-1 text-xs text-neutral-500">
                      v{c.versionNo} ({c.versionKind})
                    </span>
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{c.contractType}</td>
                  <td className="px-3 py-2 text-neutral-700">
                    {c.effectiveStart} → {c.effectiveEnd ?? "open-ended"}
                  </td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[c.status]} label={c.status} />
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{c.approvalStatus}</td>
                  <td className="px-3 py-2 text-neutral-700">{c.signatureStatus}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
