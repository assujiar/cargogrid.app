"use client";

import { useActionState } from "react";
import Link from "next/link";
import { useRouter, useSearchParams } from "next/navigation";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { StatusBadge, type StatusTone } from "../../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../../components/ui/empty-state.tsx";
import { RFQ_STATUSES, type Rfq, type RfqStatus } from "../../../../../server/contracts/rfq/rfq.ts";
import type { RfqActionState } from "./actions.ts";

const INITIAL_STATE: RfqActionState = { error: null };

const STATUS_TONE: Record<RfqStatus, StatusTone> = {
  draft: "neutral",
  issued: "info",
  closed: "success",
  cancelled: "danger",
  superseded: "neutral",
};

type BoundFormAction = (prevState: RfqActionState, formData: FormData) => Promise<RfqActionState>;

export function RfqQueuePanel({
  tenantSlug,
  rfqs,
  statusFilter,
  draftAction,
}: {
  tenantSlug: string;
  rfqs: readonly Rfq[];
  statusFilter: RfqStatus | null;
  draftAction: BoundFormAction;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const [draftState, draftFormAction, draftPending] = useActionState(draftAction, INITIAL_STATE);

  function applyStatusFilter(nextStatus: string) {
    const next = new URLSearchParams(searchParams.toString());
    if (nextStatus) next.set("status", nextStatus);
    else next.delete("status");
    router.push(`/${tenantSlug}/procurement/rfq?${next.toString()}`);
  }

  return (
    <div className="flex flex-col gap-4">
      <form action={draftFormAction} className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4 sm:flex-row sm:items-end sm:gap-3" noValidate>
        <div className="flex-1">
          <FormField
            id="sourcingRequestId"
            label="Shortlisted sourcing request id"
            helpText="Inherits service/lanes/cargo from the sourcing request's own shortlisted candidates -- never re-typed."
            error={draftState.error ?? undefined}
          >
            <Input id="sourcingRequestId" name="sourcingRequestId" type="text" required invalid={Boolean(draftState.error)} aria-describedby={draftState.error ? "sourcingRequestId-error" : "sourcingRequestId-help"} />
          </FormField>
        </div>
        <Button type="submit" loading={draftPending} loadingLabel="Drafting…">
          Draft RFQ
        </Button>
      </form>

      <div className="flex items-center gap-2">
        <label htmlFor="rfq-status" className="text-xs font-medium text-neutral-600">
          Status
        </label>
        <Select
          id="rfq-status"
          defaultValue={statusFilter ?? ""}
          className="w-auto py-1.5"
          onChange={(event) => applyStatusFilter(event.currentTarget.value)}
        >
          <option value="">All (excludes superseded)</option>
          {RFQ_STATUSES.map((s) => (
            <option key={s} value={s}>
              {s}
            </option>
          ))}
        </Select>
      </div>

      {rfqs.length === 0 ? (
        <EmptyState title="No RFQs match this view" description="Draft one above from a shortlisted sourcing request." />
      ) : (
        <div className="overflow-x-auto rounded-md border border-neutral-200">
          <table className="w-full text-sm">
            <thead className="bg-neutral-50 text-left text-xs font-medium uppercase text-neutral-500">
              <tr>
                <th className="px-3 py-2">RFQ number</th>
                <th className="px-3 py-2">Lane</th>
                <th className="px-3 py-2">Service</th>
                <th className="px-3 py-2">Status</th>
                <th className="px-3 py-2">Response deadline</th>
              </tr>
            </thead>
            <tbody>
              {rfqs.map((rfq) => (
                <tr key={rfq.id} className="border-t border-neutral-200">
                  <td className="px-3 py-2">
                    <Link href={`/${tenantSlug}/procurement/rfq/${rfq.id}`} className="font-medium text-primary hover:underline">
                      {rfq.rfqNumber}
                    </Link>
                    <span className="ml-1 text-xs text-neutral-500">v{rfq.version}</span>
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {rfq.originLane} → {rfq.destinationLane}
                  </td>
                  <td className="px-3 py-2 text-neutral-700">
                    {rfq.serviceType}
                    {rfq.mode ? ` (${rfq.mode})` : ""}
                  </td>
                  <td className="px-3 py-2">
                    <StatusBadge tone={STATUS_TONE[rfq.status]} label={rfq.status} />
                  </td>
                  <td className="px-3 py-2 text-neutral-700">{rfq.responseDeadlineAt ? new Date(rfq.responseDeadlineAt).toLocaleString() : "—"}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
