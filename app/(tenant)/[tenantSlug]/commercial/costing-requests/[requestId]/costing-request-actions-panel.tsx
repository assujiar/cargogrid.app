"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { assignCostingRequestAction, submitCostingResponseAction, reviseCostingRequestAction, cancelCostingRequestAction } from "./actions.ts";
import type { CostingResponseSourceType } from "../../../../../../server/contracts/costing/costing.ts";
import type { CostingRequestComponent } from "../../../../../../server/contracts/costing/costing.ts";

/** Assign/respond/revise/cancel action panel (COM-148) -- mirrors every prior Commercial capability's own `*-actions-panel.tsx` pattern (bound Server Actions called directly via `useTransition`). */
export function CostingRequestActionsPanel({
  tenantSlug,
  requestId,
  recordVersion,
  status,
  requestComponents,
}: {
  tenantSlug: string;
  requestId: string;
  recordVersion: number;
  status: string;
  requestComponents: readonly CostingRequestComponent[];
}) {
  const [assigneeUserId, setAssigneeUserId] = useState("");
  const [sourceType, setSourceType] = useState<CostingResponseSourceType>("internal");
  const [vendorRef, setVendorRef] = useState("");
  const [currency, setCurrency] = useState("");
  const [expiryAt, setExpiryAt] = useState("");
  const [amounts, setAmounts] = useState<Record<string, string>>({});
  const [cancelReason, setCancelReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  const isClosed = status === "cancelled" || status === "superseded";

  return (
    <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? (
        <p role="alert" className="text-sm text-danger">
          {error}
        </p>
      ) : null}

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Assign</h3>
        <input placeholder="Assignee user ID" value={assigneeUserId} onChange={(e) => setAssigneeUserId(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <Button
          type="button"
          variant="secondary"
          disabled={isClosed || !assigneeUserId.trim()}
          loading={pending}
          loadingLabel="Assigning…"
          onClick={() =>
            startTransition(async () => {
              const result = await assignCostingRequestAction(tenantSlug, requestId, recordVersion, assigneeUserId.trim());
              setError(result.error);
            })
          }
        >
          Assign
        </Button>
      </div>

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Submit response</h3>
        <select value={sourceType} onChange={(e) => setSourceType(e.target.value as CostingResponseSourceType)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm">
          <option value="internal">Internal</option>
          <option value="vendor">Vendor</option>
        </select>
        {sourceType === "vendor" ? (
          <input placeholder="Vendor reference" value={vendorRef} onChange={(e) => setVendorRef(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        ) : null}
        <input placeholder="Currency (e.g. IDR)" value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} disabled={isClosed} className="w-32 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <input type="datetime-local" placeholder="Expiry (optional)" value={expiryAt} onChange={(e) => setExpiryAt(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        {requestComponents.length === 0 ? (
          <p className="text-xs text-neutral-500">This request has no line items to price.</p>
        ) : (
          requestComponents.map((component) => (
            <div key={component.id} className="flex items-center gap-2">
              <span className="w-40 text-sm text-neutral-700">{component.componentCode}</span>
              <input
                type="number"
                min={0}
                placeholder="Amount"
                value={amounts[component.id] ?? ""}
                onChange={(e) => setAmounts((prev) => ({ ...prev, [component.id]: e.target.value }))}
                disabled={isClosed}
                className="w-32 rounded-md border border-neutral-300 px-2 py-1 text-sm"
              />
            </div>
          ))
        )}
        <Button
          type="button"
          disabled={isClosed || requestComponents.length === 0 || !/^[A-Z]{3}$/.test(currency) || (sourceType === "vendor" && !vendorRef.trim())}
          loading={pending}
          loadingLabel="Submitting…"
          onClick={() =>
            startTransition(async () => {
              const components = requestComponents
                .filter((component) => amounts[component.id]?.trim())
                .map((component) => ({ requestComponentId: component.id, amount: Number(amounts[component.id]) }));
              const result = await submitCostingResponseAction(
                tenantSlug,
                requestId,
                sourceType,
                sourceType === "vendor" ? vendorRef.trim() : null,
                currency,
                expiryAt ? new Date(expiryAt).toISOString() : null,
                components,
              );
              setError(result.error);
            })
          }
        >
          Submit response
        </Button>
      </div>

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Revise</h3>
        <p className="text-xs text-neutral-500">Creates a new request pinned to the opportunity&apos;s current requirements; this request becomes superseded but stays reachable.</p>
        <Button
          type="button"
          variant="secondary"
          disabled={isClosed}
          loading={pending}
          loadingLabel="Revising…"
          onClick={() =>
            startTransition(async () => {
              const result = await reviseCostingRequestAction(tenantSlug, requestId);
              setError(result.error);
            })
          }
        >
          Revise
        </Button>
      </div>

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Cancel</h3>
        <input placeholder="Cancel reason" value={cancelReason} onChange={(e) => setCancelReason(e.target.value)} disabled={isClosed} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        <Button
          type="button"
          variant="destructive"
          disabled={isClosed || !cancelReason.trim()}
          loading={pending}
          loadingLabel="Cancelling…"
          onClick={() =>
            startTransition(async () => {
              const result = await cancelCostingRequestAction(tenantSlug, requestId, recordVersion, cancelReason.trim());
              setError(result.error);
            })
          }
        >
          Cancel
        </Button>
      </div>
    </div>
  );
}
