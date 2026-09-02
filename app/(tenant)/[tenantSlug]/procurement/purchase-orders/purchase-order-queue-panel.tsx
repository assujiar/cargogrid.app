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
import { PURCHASE_ORDER_STATUSES, type PurchaseOrder, type PurchaseOrderStatus } from "../../../../../server/contracts/purchase-order/purchase-order.ts";
import type { PurchaseOrderActionState } from "./actions.ts";

const INITIAL_STATE: PurchaseOrderActionState = { error: null };

const STATUS_TONE: Record<PurchaseOrderStatus, StatusTone> = {
  draft: "neutral",
  submitted: "info",
  issued: "success",
  acknowledged: "success",
  cancelled: "danger",
  superseded: "neutral",
};

type BoundFormAction = (prevState: PurchaseOrderActionState, formData: FormData) => Promise<PurchaseOrderActionState>;

export function PurchaseOrderQueuePanel({
  tenantSlug,
  purchaseOrders,
  statusFilter,
  draftAction,
}: {
  tenantSlug: string;
  purchaseOrders: readonly PurchaseOrder[];
  statusFilter: PurchaseOrderStatus | null;
  draftAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [draftState, draftFormAction, draftPending] = useActionState(draftAction, INITIAL_STATE);
  const draftErrorId = "po-draft-error";
  const draftDescribedBy = draftState.error ? draftErrorId : undefined;

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/purchase-orders?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <form action={draftFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
          <div className="sm:col-span-2">
            <FormField id="comparisonId" label="Approved vendor comparison id (required)">
              <Input id="comparisonId" name="comparisonId" type="text" required invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
            </FormField>
          </div>
          <FormField id="taxCode" label="Tax code (optional)">
            <Input id="taxCode" name="taxCode" type="text" invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
          </FormField>
          <FormField id="paymentTermDays" label="Payment term days (defaults to vendor)">
            <Input id="paymentTermDays" name="paymentTermDays" type="number" min={0} invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
          </FormField>
          <FormField id="expectedDeliveryDate" label="Expected delivery date">
            <Input id="expectedDeliveryDate" name="expectedDeliveryDate" type="date" invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
          </FormField>
          <FormField id="servicePeriodStart" label="Service period start">
            <Input id="servicePeriodStart" name="servicePeriodStart" type="date" invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
          </FormField>
          <FormField id="servicePeriodEnd" label="Service period end">
            <Input id="servicePeriodEnd" name="servicePeriodEnd" type="date" invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
          </FormField>
          <div className="sm:col-span-2">
            <FormField id="commercialTerms" label="Commercial terms">
              <Input id="commercialTerms" name="commercialTerms" type="text" invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
            </FormField>
          </div>
          <div className="sm:col-span-2">
            <FormField id="notes" label="Notes">
              <Input id="notes" name="notes" type="text" invalid={Boolean(draftState.error)} aria-describedby={draftDescribedBy} />
            </FormField>
          </div>
        </div>
        {draftState.error ? <ValidationMessage id={draftErrorId}>{draftState.error}</ValidationMessage> : null}
        <Button type="submit" loading={draftPending} loadingLabel="Drafting…" className="w-fit">
          Draft purchase order
        </Button>
      </form>

      <div className="flex items-center gap-2">
        <label htmlFor="po-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <Select id="po-status" defaultValue={statusFilter ?? ""} className="w-auto py-1.5" onChange={(event) => applyStatusFilter(event.currentTarget.value)}>
          <option value="">All (excludes superseded)</option>
          {PURCHASE_ORDER_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
      </div>

      {purchaseOrders.length === 0 ? (
        <EmptyState title="No purchase orders match this view" description="Draft one above from an approved, submitted vendor comparison selection." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">PO number</th>
                <th className="px-3 py-2">Total</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Approval</th>
                <th className="px-3 py-2">Fulfillment</th>
              </tr>
            </thead>
            <tbody>
              {purchaseOrders.map((po) => (
                <tr key={po.id} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/purchase-orders/${po.id}`} className="font-medium text-primary hover:underline">
                      {po.poNumber}
                    </Link>
                    <span className="ml-1 text-xs text-neutral-500">v{po.version}</span>
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{po.costMasked ? "Masked" : po.totalAmount !== null ? `${po.currency ?? ""} ${po.totalAmount.toLocaleString()}` : "—"}</td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[po.status]} label={po.status} />
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{po.approvalStatus}</td>
                  <td className="px-3 py-2 text-neutral-700">{po.fulfillmentStatus}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
