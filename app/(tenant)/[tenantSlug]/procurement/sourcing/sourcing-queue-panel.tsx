"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
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
          <label htmlFor="costingRequestId" className="text-xs font-medium text-neutral-700">
            Costing request id
          </label>
          <Input id="costingRequestId" name="costingRequestId" type="text" required />
          <label htmlFor="costingSlaDueAt" className="text-xs font-medium text-neutral-700">
            SLA due (optional)
          </label>
          <Input id="costingSlaDueAt" name="slaDueAt" type="datetime-local" />
          {costingState.error ? (
            <p role="alert" className="text-sm text-danger">
              {costingState.error}
            </p>
          ) : null}
          <Button type="submit" loading={costingPending} loadingLabel="Creating…">
            Create from costing request
          </Button>
        </form>

        <form action={demandFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
          <h2 className="text-sm font-semibold text-neutral-900">From a shipment order</h2>
          <p className="text-xs text-neutral-500">Inherits service/mode/lanes/cargo from the Operations shipment order. Starts open directly.</p>
          <label htmlFor="shipmentOrderId" className="text-xs font-medium text-neutral-700">
            Shipment order id
          </label>
          <Input id="shipmentOrderId" name="shipmentOrderId" type="text" required />
          <label htmlFor="demandSlaDueAt" className="text-xs font-medium text-neutral-700">
            SLA due (optional)
          </label>
          <Input id="demandSlaDueAt" name="slaDueAt" type="datetime-local" />
          {demandState.error ? (
            <p role="alert" className="text-sm text-danger">
              {demandState.error}
            </p>
          ) : null}
          <Button type="submit" loading={demandPending} loadingLabel="Creating…">
            Create from shipment order
          </Button>
        </form>

        <form action={proactiveFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4" noValidate>
          <h2 className="text-sm font-semibold text-neutral-900">Proactive sourcing</h2>
          <p className="text-xs text-neutral-500">No source demand -- starts draft, needs submit to reach open.</p>
          <div className="grid grid-cols-2 gap-2">
            <div className="flex flex-col gap-1">
              <label htmlFor="serviceType" className="text-xs font-medium text-neutral-700">
                Service type
              </label>
              <Input id="serviceType" name="serviceType" type="text" placeholder="ocean_freight" required />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="mode" className="text-xs font-medium text-neutral-700">
                Mode (optional)
              </label>
              <Input id="mode" name="mode" type="text" placeholder="FCL" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="originLane" className="text-xs font-medium text-neutral-700">
                Origin
              </label>
              <Input id="originLane" name="originLane" type="text" required />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="destinationLane" className="text-xs font-medium text-neutral-700">
                Destination
              </label>
              <Input id="destinationLane" name="destinationLane" type="text" required />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="currency" className="text-xs font-medium text-neutral-700">
                Currency (optional)
              </label>
              <Input id="currency" name="currency" type="text" maxLength={3} placeholder="IDR" />
            </div>
            <div className="flex flex-col gap-1">
              <label htmlFor="budgetAmount" className="text-xs font-medium text-neutral-700">
                Budget (optional)
              </label>
              <Input id="budgetAmount" name="budgetAmount" type="number" min={0} />
            </div>
          </div>
          {proactiveState.error ? (
            <p role="alert" className="text-sm text-danger">
              {proactiveState.error}
            </p>
          ) : null}
          <Button type="submit" loading={proactivePending} loadingLabel="Creating…">
            Start proactive sourcing
          </Button>
        </form>
      </div>

      <div className="flex items-center gap-2">
        <label htmlFor="sourcing-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <select
          id="sourcing-status"
          defaultValue={statusFilter ?? ""}
          className="rounded-md border border-neutral-300 px-3 py-1.5 text-sm"
          onChange={(event) => applyStatusFilter(event.currentTarget.value)}
        >
          <option value="">All statuses</option>
          {SOURCING_REQUEST_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s.replace(/_/g, " ")}
            </option>
          ))}
        </select>
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
