"use client";

import Link from "next/link";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { CreateProcurementRateForm } from "./create-procurement-rate-form.tsx";
import type { ProcurementRateActionState } from "./actions.ts";
import type { RateVersionApprovalStatus } from "../../../../../server/contracts/rate/rate.ts";

const STATUS_TONE: Record<RateVersionApprovalStatus, StatusTone> = {
  pending_approval: "info",
  approved: "success",
  rejected: "danger",
  withdrawn: "neutral",
  superseded: "neutral",
};

export interface ProcurementRateRow {
  readonly rateVersionId: string;
  readonly vendorCode: string;
  readonly vendorName: string;
  readonly serviceType: string;
  readonly originLane: string;
  readonly destinationLane: string;
  readonly approvalStatus: RateVersionApprovalStatus;
  readonly currency: string | null;
  readonly baseAmount: number | null;
  readonly costMasked: boolean;
  readonly vendorMasterId: string | null;
}

export function RateDirectoryPanel({
  tenantSlug,
  rates,
  createAction,
}: {
  tenantSlug: string;
  rates: readonly ProcurementRateRow[];
  createAction: (prevState: ProcurementRateActionState, formData: FormData) => Promise<ProcurementRateActionState>;
}) {
  return (
    <div className="flex flex-col gap-4">
      <CreateProcurementRateForm action={createAction} />

      {rates.length === 0 ? (
        <EmptyState
          title="No procurement-linked vendor rates yet"
          description="Rates linked to a registered vendor (ADR-0020) appear here. Create one above, or link an existing Commercial rate from its own detail page."
        />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">Vendor</th>
                <th className="px-3 py-2">Lane</th>
                <th className="px-3 py-2">Service</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Cost</th>
                <th className="px-3 py-2">Linked</th>
              </tr>
            </thead>
            <tbody>
              {rates.map((rate) => (
                <tr key={rate.rateVersionId} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/rates/${rate.rateVersionId}`} className="font-medium text-primary hover:underline">
                      {rate.vendorName} ({rate.vendorCode})
                    </Link>
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {rate.originLane} → {rate.destinationLane}
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{rate.serviceType}</td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[rate.approvalStatus]} label={rate.approvalStatus.replace("_", " ")} />
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {rate.costMasked ? <span className="italic text-neutral-400">masked</span> : `${rate.currency ?? ""} ${rate.baseAmount ?? ""}`}
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{rate.vendorMasterId ? "Yes" : "No"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
