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
import { VENDOR_ASSIGNMENT_INVITATION_STATUSES, type VendorAssignmentInvitation, type VendorAssignmentInvitationStatus } from "../../../../../server/contracts/vendor-assignment/vendor-assignment.ts";
import type { VendorProfileListRow } from "../../../../../server/contracts/vendor-profile/vendor-profile.ts";
import type { VendorAssignmentActionState } from "./actions.ts";

const INITIAL_STATE: VendorAssignmentActionState = { error: null };

const STATUS_TONE: Record<VendorAssignmentInvitationStatus, StatusTone> = {
  invited: "info",
  accepted: "info",
  declined: "danger",
  expired: "neutral",
  assigned: "success",
  cancelled: "neutral",
  superseded: "neutral",
};

type BoundFormAction = (prevState: VendorAssignmentActionState, formData: FormData) => Promise<VendorAssignmentActionState>;

export function VendorAssignmentQueuePanel({
  tenantSlug,
  invitations,
  activeVendors,
  statusFilter,
  proposeAction,
  overrideAction,
}: {
  tenantSlug: string;
  invitations: readonly VendorAssignmentInvitation[];
  activeVendors: readonly VendorProfileListRow[];
  statusFilter: VendorAssignmentInvitationStatus | null;
  proposeAction: BoundFormAction;
  overrideAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [proposeState, proposeFormAction, proposePending] = useActionState(proposeAction, INITIAL_STATE);
  const [overrideState, overrideFormAction, overridePending] = useActionState(overrideAction, INITIAL_STATE);
  const proposeErrorId = "vasm-propose-error";
  const proposeDescribedBy = proposeState.error ? proposeErrorId : undefined;
  const overrideErrorId = "vasm-override-error";
  const overrideDescribedBy = overrideState.error ? overrideErrorId : undefined;

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/vendor-assignments?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <form action={proposeFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
        <h2 className="text-sm font-semibold text-neutral-900">Propose an invitation</h2>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-4">
          <div className="sm:col-span-2">
            <FormField id="propose-shipmentOrderId" label="Shipment order ID (required)">
              <Input id="propose-shipmentOrderId" name="shipmentOrderId" type="text" required placeholder="uuid" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} />
            </FormField>
          </div>
          <div className="sm:col-span-2">
            <FormField id="propose-vendorMasterId" label="Vendor (required, active only)">
              <Select id="propose-vendorMasterId" name="vendorMasterId" required invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy}>
                <option value="">Select a vendor…</option>
                {activeVendors.map((v) => (
                  <option key={v.masterRecordId} value={v.masterRecordId}>
                    {v.legalName} ({v.vendorCode})
                  </option>
                ))}
              </Select>
            </FormField>
          </div>
          <FormField id="propose-contractId" label="Governing contract ID">
            <Input id="propose-contractId" name="contractId" type="text" placeholder="optional uuid" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} />
          </FormField>
          <FormField id="propose-capacityReservationId" label="Capacity reservation ID">
            <Input id="propose-capacityReservationId" name="capacityReservationId" type="text" placeholder="optional uuid" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} />
          </FormField>
          <FormField id="propose-poId" label="PO ID">
            <Input id="propose-poId" name="poId" type="text" placeholder="optional uuid" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} />
          </FormField>
          <FormField id="propose-responseDeadline" label="Response deadline">
            <Input id="propose-responseDeadline" name="responseDeadline" type="date" invalid={Boolean(proposeState.error)} aria-describedby={proposeDescribedBy} />
          </FormField>
        </div>
        {proposeState.error ? <ValidationMessage id={proposeErrorId}>{proposeState.error}</ValidationMessage> : null}
        <Button type="submit" loading={proposePending} loadingLabel="Proposing…" className="w-fit">
          Propose invitation
        </Button>
      </form>

      <form action={overrideFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
        <h2 className="text-sm font-semibold text-neutral-900">Emergency override</h2>
        <p className="text-xs text-neutral-500">Bypasses the normal invite/accept/eligibility gate entirely. Requires both OPS:Assign and PRC:Override. No formal expiry/later-review workflow exists yet -- disclosed, not silently equivalent to a normal confirmed assignment.</p>
        <div className="grid grid-cols-1 gap-2 sm:grid-cols-3">
          <FormField id="override-shipmentOrderId" label="Shipment order ID (required)">
            <Input id="override-shipmentOrderId" name="shipmentOrderId" type="text" required placeholder="uuid" invalid={Boolean(overrideState.error)} aria-describedby={overrideDescribedBy} />
          </FormField>
          <FormField id="override-vendorMasterId" label="Vendor (required)">
            <Select id="override-vendorMasterId" name="vendorMasterId" required invalid={Boolean(overrideState.error)} aria-describedby={overrideDescribedBy}>
              <option value="">Select a vendor…</option>
              {activeVendors.map((v) => (
                <option key={v.masterRecordId} value={v.masterRecordId}>
                  {v.legalName} ({v.vendorCode})
                </option>
              ))}
            </Select>
          </FormField>
          <FormField id="override-reason" label="Reason (required)">
            <Input id="override-reason" name="reason" type="text" required invalid={Boolean(overrideState.error)} aria-describedby={overrideDescribedBy} />
          </FormField>
        </div>
        {overrideState.error ? <ValidationMessage id={overrideErrorId}>{overrideState.error}</ValidationMessage> : null}
        <Button type="submit" variant="destructive" loading={overridePending} loadingLabel="Overriding…" className="w-fit">
          Direct-assign (override)
        </Button>
      </form>

      <div className="flex items-center gap-2">
        <label htmlFor="vasm-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <Select id="vasm-status" defaultValue={statusFilter ?? ""} className="w-auto py-1.5" onChange={(event) => applyStatusFilter(event.currentTarget.value)}>
          <option value="">All</option>
          {VENDOR_ASSIGNMENT_INVITATION_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
      </div>

      {invitations.length === 0 ? (
        <EmptyState title="No vendor assignment invitations match this view" description="Propose one above for a shipment order and an active vendor." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">Shipment order</th>
                <th className="px-3 py-2">Vendor</th>
                <th className="px-3 py-2">Override</th>
                <th className="px-3 py-2">Status</th>
              </tr>
            </thead>
            <tbody>
              {invitations.map((inv) => (
                <tr key={inv.id} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/vendor-assignments/${inv.id}`} className="font-medium text-primary hover:underline">
                      {inv.shipmentOrderId}
                    </Link>
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{inv.vendorMasterId}</td>
                  <td className="px-3 py-2 text-neutral-700">{inv.isOverride ? "Yes" : "—"}</td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[inv.status]} label={inv.status} />
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
