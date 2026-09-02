"use client";

import { useState, useTransition } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { assignCostingRequestAction, submitCostingResponseAction, reviseCostingRequestAction, cancelCostingRequestAction } from "./actions.ts";
import type { CostingResponseSourceType } from "../../../../../../server/contracts/costing/costing.ts";
import type { CostingRequestComponent } from "../../../../../../server/contracts/costing/costing.ts";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";

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

  // Four independent actions (assign / submit / revise / cancel) share this one `error`
  // slot, so there is no honest per-field attribution: every control points at the shared
  // message via `aria-describedby` and none of them claims `aria-invalid`.
  const describedBy = error ? "costing-actions-error" : undefined;

  const isClosed = status === "cancelled" || status === "superseded";

  return (
    <div className="flex flex-col gap-6 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Actions</h2>

      {error ? <ValidationMessage id="costing-actions-error">{error}</ValidationMessage> : null}

      <div className="flex flex-col gap-2">
        <h3 className="text-sm font-medium text-neutral-900">Assign</h3>
        <FormField id="costing-assignee" label={<span className="sr-only">Assignee user ID</span>}>
          <Input id="costing-assignee" placeholder="Assignee user ID" value={assigneeUserId} onChange={(e) => setAssigneeUserId(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
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
        <FormField id="costing-source-type" label={<span className="sr-only">Response source</span>}>
          <Select id="costing-source-type" value={sourceType} onChange={(e) => setSourceType(e.target.value as CostingResponseSourceType)} disabled={isClosed} aria-describedby={describedBy}>
            <option value="internal">Internal</option>
            <option value="vendor">Vendor</option>
          </Select>
        </FormField>
        {sourceType === "vendor" ? (
          <FormField id="costing-vendor-ref" label={<span className="sr-only">Vendor reference</span>}>
            <Input id="costing-vendor-ref" placeholder="Vendor reference" value={vendorRef} onChange={(e) => setVendorRef(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
          </FormField>
        ) : null}
        <div className="w-32">
          <FormField id="costing-currency" label={<span className="sr-only">Currency</span>}>
            <Input id="costing-currency" placeholder="Currency (e.g. IDR)" value={currency} onChange={(e) => setCurrency(e.target.value.toUpperCase())} disabled={isClosed} aria-describedby={describedBy} />
          </FormField>
        </div>
        <FormField id="costing-expiry" label={<span className="sr-only">Expiry (optional)</span>}>
          <Input id="costing-expiry" type="datetime-local" placeholder="Expiry (optional)" value={expiryAt} onChange={(e) => setExpiryAt(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
        {requestComponents.length === 0 ? (
          <p className="text-xs text-neutral-500">This request has no line items to price.</p>
        ) : (
          requestComponents.map((component) => (
            <div key={component.id} className="flex items-center gap-2">
              {/* The component code was already the visual label for this row's amount --
                  it is now a real `<label htmlFor>`, so the association is programmatic too. */}
              <label htmlFor={`costing-amount-${component.id}`} className="w-40 text-sm text-neutral-700">
                {component.componentCode}
              </label>
              <div className="w-32">
                <NumberInput
                  id={`costing-amount-${component.id}`}
                  min={0}
                  placeholder="Amount"
                  value={amounts[component.id] ?? ""}
                  onChange={(e) => setAmounts((prev) => ({ ...prev, [component.id]: e.target.value }))}
                  disabled={isClosed}
                  aria-describedby={describedBy}
                />
              </div>
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
        <FormField id="costing-cancel-reason" label={<span className="sr-only">Cancel reason</span>}>
          <Input id="costing-cancel-reason" placeholder="Cancel reason" value={cancelReason} onChange={(e) => setCancelReason(e.target.value)} disabled={isClosed} aria-describedby={describedBy} />
        </FormField>
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
