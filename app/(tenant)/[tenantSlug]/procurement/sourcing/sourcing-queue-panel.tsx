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
import { SOURCING_REQUEST_STATUSES, type SourcingRequest, type SourcingRequestStatus } from "../../../../../server/contracts/sourcing/sourcing.ts";
import type { SourcingActionState } from "./actions.ts";

const INITIAL_STATE: SourcingActionState = { error: null };

const STATUS_TONE: Record<SourcingRequestStatus, StatusTone> = {
  draft: "neutral",
  open: "info",
  shortlisted: "success",
  closed_no_source: "warning",
  cancelled: "danger",
};

const SOURCE_TYPE_LABEL: Record<SourcingRequest["sourceType"], string> = {
  costing_request: "Commercial costing request",
  operational_demand: "Operations shipment order",
  proactive: "Proactive",
};

type BoundFormAction = (prevState: SourcingActionState, formData: FormData) => Promise<SourcingActionState>;

export function SourcingQueuePanel({
  tenantSlug,
  requests,
  statusFilter,
  createFromCostingAction,
  createFromOperationalDemandAction,
  createProactiveAction,
}: {
  tenantSlug: string;
  requests: readonly SourcingRequest[];
  statusFilter: SourcingRequestStatus | null;
  createFromCostingAction: BoundFormAction;
  createFromOperationalDemandAction: BoundFormAction;
  createProactiveAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();

  const [costingState, costingFormAction, costingPending] = useActionState(createFromCostingAction, INITIAL_STATE);
  const [demandState, demandFormAction, demandPending] = useActionState(createFromOperationalDemandAction, INITIAL_STATE);
  const [proactiveState, proactiveFormAction, proactivePending] = useActionState(createProactiveAction, INITIAL_STATE);
  const costingErrorId = "sourcing-costing-error";
  const costingDescribedBy = costingState.error ? costingErrorId : undefined;
  const demandErrorId = "sourcing-demand-error";
  const demandDescribedBy = demandState.error ? demandErrorId : undefined;
  const proactiveErrorId = "sourcing-proactive-error";
  const proactiveDescribedBy = proactiveState.error ? proactiveErrorId : undefined;

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/sourcing?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <form action={costingFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
          <h2 className="text-sm font-semibold text-neutral-900">From a costing request</h2>
          <p className="text-xs text-neutral-500">Inherits service/lanes from the costing request&apos;s own requirements snapshot -- never re-typed. Starts open directly.</p>
          <FormField id="costingRequestId" label="Costing request id">
            <Input id="costingRequestId" name="costingRequestId" type="text" required invalid={Boolean(costingState.error)} aria-describedby={costingDescribedBy} />
          </FormField>
          <FormField id="costingSlaDueAt" label="SLA due (optional)">
            <Input id="costingSlaDueAt" name="slaDueAt" type="datetime-local" invalid={Boolean(costingState.error)} aria-describedby={costingDescribedBy} />
          </FormField>
          {costingState.error ? <ValidationMessage id={costingErrorId}>{costingState.error}</ValidationMessage> : null}
          <Button type="submit" loading={costingPending} loadingLabel="Creating…">
            Create from costing request
          </Button>
        </form>

        <form action={demandFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
          <h2 className="text-sm font-semibold text-neutral-900">From a shipment order</h2>
          <p className="text-xs text-neutral-500">Inherits service/mode/lanes/cargo from the Operations shipment order. Starts open directly.</p>
          <FormField id="shipmentOrderId" label="Shipment order id">
            <Input id="shipmentOrderId" name="shipmentOrderId" type="text" required invalid={Boolean(demandState.error)} aria-describedby={demandDescribedBy} />
          </FormField>
          <FormField id="demandSlaDueAt" label="SLA due (optional)">
            <Input id="demandSlaDueAt" name="slaDueAt" type="datetime-local" invalid={Boolean(demandState.error)} aria-describedby={demandDescribedBy} />
          </FormField>
          {demandState.error ? <ValidationMessage id={demandErrorId}>{demandState.error}</ValidationMessage> : null}
          <Button type="submit" loading={demandPending} loadingLabel="Creating…">
            Create from shipment order
          </Button>
        </form>

        <form action={proactiveFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
          <h2 className="text-sm font-semibold text-neutral-900">Proactive sourcing</h2>
          <p className="text-xs text-neutral-500">No source demand -- starts draft, needs submit to reach open.</p>
          <div className="grid grid-cols-2 gap-2">
            <FormField id="serviceType" label="Service type">
              <Input id="serviceType" name="serviceType" type="text" placeholder="ocean_freight" required invalid={Boolean(proactiveState.error)} aria-describedby={proactiveDescribedBy} />
            </FormField>
            <FormField id="mode" label="Mode (optional)">
              <Input id="mode" name="mode" type="text" placeholder="FCL" invalid={Boolean(proactiveState.error)} aria-describedby={proactiveDescribedBy} />
            </FormField>
            <FormField id="originLane" label="Origin">
              <Input id="originLane" name="originLane" type="text" required invalid={Boolean(proactiveState.error)} aria-describedby={proactiveDescribedBy} />
            </FormField>
            <FormField id="destinationLane" label="Destination">
              <Input id="destinationLane" name="destinationLane" type="text" required invalid={Boolean(proactiveState.error)} aria-describedby={proactiveDescribedBy} />
            </FormField>
            <FormField id="currency" label="Currency (optional)">
              <Input id="currency" name="currency" type="text" maxLength={3} placeholder="IDR" invalid={Boolean(proactiveState.error)} aria-describedby={proactiveDescribedBy} />
            </FormField>
            <FormField id="budgetAmount" label="Budget (optional)">
              <Input id="budgetAmount" name="budgetAmount" type="number" min={0} invalid={Boolean(proactiveState.error)} aria-describedby={proactiveDescribedBy} />
            </FormField>
          </div>
          {proactiveState.error ? <ValidationMessage id={proactiveErrorId}>{proactiveState.error}</ValidationMessage> : null}
          <Button type="submit" loading={proactivePending} loadingLabel="Creating…">
            Start proactive sourcing
          </Button>
        </form>
      </div>

      <div className="flex items-center gap-2">
        <label htmlFor="sourcing-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <Select
          id="sourcing-status"
          defaultValue={statusFilter ?? ""}
          className="w-auto py-1.5"
          onChange={(event) => applyStatusFilter(event.currentTarget.value)}
        >
          <option value="">All statuses</option>
          {SOURCING_REQUEST_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s.replace(/_/g, " ")}
            </option>
          ))}
        </Select>
      </div>

      {requests.length === 0 ? (
        <EmptyState title="No sourcing requests match this view" description="Create one above -- from a costing request, a shipment order, or proactively." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">Lane</th>
                <th className="px-3 py-2">Service</th>
                <th className="px-3 py-2">Source</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">SLA due</th>
              </tr>
            </thead>
            <tbody>
              {requests.map((request) => (
                <tr key={request.id} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/sourcing/${request.id}`} className="font-medium text-primary hover:underline">
                      {request.originLane} → {request.destinationLane}
                    </Link>
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {request.serviceType}
                    {request.mode ? ` (${request.mode})` : ""}
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{SOURCE_TYPE_LABEL[request.sourceType]}</td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[request.status]} label={request.status.replace(/_/g, " ")} />
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{request.slaDueAt ? new Date(request.slaDueAt).toLocaleString() : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
