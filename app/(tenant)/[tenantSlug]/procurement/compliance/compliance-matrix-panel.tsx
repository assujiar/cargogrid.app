"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import type { ComplianceActionState } from "./actions.ts";
import { VENDOR_COMPLIANCE_STATUSES, type VendorComplianceStatusValue, type VendorComplianceMatrixRow } from "../../../../../server/contracts/vendor-compliance/vendor-compliance.ts";

const INITIAL_STATE: ComplianceActionState = { error: null };

const STATUS_TONE: Record<VendorComplianceStatusValue, StatusTone> = {
  not_submitted: "neutral",
  pending_verification: "info",
  verified: "success",
  expiring_soon: "warning",
  expired: "danger",
  waived: "info",
  rejected: "danger",
};

export function ComplianceMatrixPanel({
  tenantSlug,
  rows,
  statusFilter,
  holdOnly,
  recalculateTenantAction,
}: {
  tenantSlug: string;
  rows: readonly VendorComplianceMatrixRow[];
  statusFilter: VendorComplianceStatusValue | null;
  holdOnly: boolean;
  recalculateTenantAction: (prevState: ComplianceActionState, formData: FormData) => Promise<ComplianceActionState>;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [state, formAction, pending] = useActionState(recalculateTenantAction, INITIAL_STATE);

  function applyFilter(nextStatus: string, nextHold: boolean) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    if (nextHold) next.set("hold", "1");
    else next.delete("hold");
    next.delete("after");
    router.push(`/${tenantSlug}/procurement/compliance?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
        <div className="flex flex-wrap items-end gap-3">
          <div className="flex gap-1 rounded-md border border-neutral-300 p-1 text-sm">
            <button type="button" onClick={() => applyFilter("", false)} className={`rounded px-3 py-1 ${!statusFilter && !holdOnly ? "bg-primary text-neutral-50" : ""}`}>
              All
            </button>
            <button type="button" onClick={() => applyFilter("", true)} className={`rounded px-3 py-1 ${holdOnly ? "bg-primary text-neutral-50" : ""}`}>
              Eligibility holds
            </button>
            <button type="button" onClick={() => applyFilter("expiring_soon", false)} className={`rounded px-3 py-1 ${statusFilter === "expiring_soon" ? "bg-primary text-neutral-50" : ""}`}>
              Expiring soon
            </button>
            <button type="button" onClick={() => applyFilter("expired", false)} className={`rounded px-3 py-1 ${statusFilter === "expired" ? "bg-primary text-neutral-50" : ""}`}>
              Expired
            </button>
          </div>
          <div className="flex flex-col gap-1">
            <label htmlFor="compliance-status" className="text-xs font-medium text-neutral-600">
              Status
            </label>
            <select id="compliance-status" defaultValue={statusFilter ?? ""} className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm" onChange={(event) => applyFilter(event.currentTarget.value, holdOnly)}>
              <option value="">All statuses</option>
              {VENDOR_COMPLIANCE_STATUSES.map((s) => (
                <option key={s} value={s}>
                  {s.replace(/_/g, " ")}
                </option>
              ))}
            </select>
          </div>
          <form action={formAction} className="ml-auto flex flex-col gap-1">
            <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recalculating…">
              Recalculate all
            </Button>
          </form>
        </div>
        {state.error ? (
          <p role="alert" className="text-sm text-danger">
            {state.error}
          </p>
        ) : null}

        {rows.length === 0 ? (
          <EmptyState title="No compliance rows match this view" description="Adjust your filters, or publish a requirement so vendors have something to submit against." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-left text-xs text-neutral-500">
                <th className="pb-1">Vendor</th>
                <th className="pb-1">Requirement</th>
                <th className="pb-1">Blocking</th>
                <th className="pb-1">Status</th>
                <th className="pb-1">Hold</th>
                <th className="pb-1">Expiry</th>
                <th className="pb-1">Reminder tier</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={row.statusId} className="border-t border-neutral-100">
                  <td className="py-1">
                    <Link href={`/${tenantSlug}/procurement/compliance/vendors/${row.vendorMasterRecordId}`} className="text-primary underline">
                      {row.vendorLegalName}
                    </Link>
                  </td>
                  <td className="py-1">{row.requirementName ?? "—"}</td>
                  <td className="py-1 text-xs">{row.blockingEffect ?? "—"}</td>
                  <td className="py-1">
                    <StatusBadge tone={STATUS_TONE[row.status]} label={row.status.replace(/_/g, " ")} />
                  </td>
                  <td className="py-1">{row.eligibilityHold ? <StatusBadge tone="danger" label="hold" /> : "—"}</td>
                  <td className="py-1 text-xs">{row.expiryDate ?? "—"}</td>
                  <td className="py-1 text-xs">
                    {row.reminderTierDays != null ? `${row.reminderTierDays}-day tier (${row.daysUntilExpiry}d left)` : "—"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>
    </div>
  );
}
