"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { ShipmentActualCostDirectoryRow, ShipmentActualCostComponent, ActualCostVariance } from "../../../../../../server/contracts/actual-cost/actual-cost.ts";
import type { AssignmentCandidate } from "../../../../../../server/contracts/resource-assignment/resource-assignment.ts";
import type { ShipmentOrderFormState } from "./actions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

const STATUS_TONE: Record<ShipmentActualCostDirectoryRow["status"], "success" | "warning" | "danger" | "neutral"> = {
  draft: "neutral",
  submitted: "warning",
  approved: "success",
  rejected: "danger",
};

/** OPS-178: componentized actual-cost workbench -- create/add-component/remove/submit/decide/adjust forms, plus a masked total when the actor lacks OPS:View cost (cost is hidden entirely, not fabricated as zero). */
export function ActualCostPanel({
  cost,
  costMasked,
  components,
  variance,
  vendors,
  createAction,
  addComponentAction,
  removeComponentAction,
  submitAction,
  decideAction,
  adjustAction,
}: {
  readonly cost: ShipmentActualCostDirectoryRow | null;
  readonly costMasked: boolean;
  readonly components: readonly ShipmentActualCostComponent[];
  readonly variance: ActualCostVariance | null;
  readonly vendors: readonly AssignmentCandidate[];
  readonly createAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly addComponentAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly removeComponentAction: (componentId: string) => (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly submitAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly decideAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly adjustAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [createState, createFormAction, createPending] = useActionState(createAction, INITIAL_STATE);

  if (!cost) {
    return (
      <form action={createFormAction} className="flex flex-wrap items-end gap-2" noValidate>
        <label className="flex flex-col text-sm text-neutral-700">
          Currency
          <input type="text" name="currency" required defaultValue="IDR" className="w-20 rounded border border-neutral-300 px-2 py-1" />
        </label>
        <label className="flex flex-col text-sm text-neutral-700">
          Estimated amount (optional)
          <input type="number" name="estimatedAmount" min={0} step="any" className="w-40 rounded border border-neutral-300 px-2 py-1" />
        </label>
        <Button type="submit" loading={createPending} loadingLabel="Starting…">
          Start actual cost
        </Button>
        {createState.error ? (
          <p role="alert" className="mt-1 text-sm text-danger">
            {createState.error}
          </p>
        ) : null}
      </form>
    );
  }

  if (costMasked) {
    return (
      <div className="flex items-center gap-2">
        <StatusBadge tone={STATUS_TONE[cost.status]} label={cost.status} />
        <span className="text-sm text-neutral-500">Cost amounts are restricted (requires OPS:View cost).</span>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-3">
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge tone={STATUS_TONE[cost.status]} label={cost.status} />
        <span className="text-sm text-neutral-700">v{cost.versionNumber}</span>
        <span className="text-sm font-medium text-neutral-900">
          Total: {cost.totalAmount?.toLocaleString()} {cost.currency}
        </span>
        {variance?.varianceAvailable ? (
          <span className="text-sm text-neutral-700">
            Variance: {variance.varianceAmount?.toLocaleString()} {cost.currency}
          </span>
        ) : null}
      </div>
      {cost.rejectionReason ? <p className="text-sm text-danger">Rejected: {cost.rejectionReason}</p> : null}

      {components.length > 0 ? (
        <ul className="flex flex-col gap-2">
          {components.map((component) => (
            <ComponentRow key={component.id} component={component} draft={cost.status === "draft"} removeAction={removeComponentAction(component.id)} />
          ))}
        </ul>
      ) : (
        <p className="text-sm text-neutral-500">No cost components recorded yet.</p>
      )}

      {cost.status === "draft" ? <AddComponentForm addComponentAction={addComponentAction} vendors={vendors} /> : null}

      {cost.status === "draft" ? <SubmitForm submitAction={submitAction} /> : null}
      {cost.status === "submitted" ? <DecideForm decideAction={decideAction} /> : null}
      {cost.status === "approved" ? <AdjustForm adjustAction={adjustAction} /> : null}
    </div>
  );
}

function ComponentRow({
  component,
  draft,
  removeAction,
}: {
  readonly component: ShipmentActualCostComponent;
  readonly draft: boolean;
  readonly removeAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [removeState, removeFormAction, removePending] = useActionState(removeAction, INITIAL_STATE);
  return (
    <li className="flex flex-wrap items-center gap-2 rounded-md border border-neutral-200 p-2 text-sm">
      <span className="font-medium text-neutral-900">{component.category}</span>
      <span className="text-neutral-600">
        {component.quantity} × {component.rate.toLocaleString()} {component.uom ?? ""}
      </span>
      <span className="font-medium text-neutral-900">
        = {component.amount.toLocaleString()} {component.currency}
      </span>
      <span className="text-xs uppercase tracking-wide text-neutral-500">{component.sourceType}</span>
      {draft ? (
        <form action={removeFormAction}>
          <Button type="submit" variant="destructive" loading={removePending} loadingLabel="Removing…">
            Remove
          </Button>
        </form>
      ) : null}
      {removeState.error ? (
        <p role="alert" className="text-sm text-danger">
          {removeState.error}
        </p>
      ) : null}
    </li>
  );
}

function AddComponentForm({
  addComponentAction,
  vendors,
}: {
  readonly addComponentAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  readonly vendors: readonly AssignmentCandidate[];
}) {
  const [state, formAction, pending] = useActionState(addComponentAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 border-t border-neutral-200 pt-2" noValidate>
      <label className="flex flex-col text-sm text-neutral-700">
        Category
        <select name="category" required defaultValue="freight" className="rounded border border-neutral-300 px-2 py-1">
          <option value="freight">freight</option>
          <option value="trucking">trucking</option>
          <option value="fuel_surcharge">fuel_surcharge</option>
          <option value="handling">handling</option>
          <option value="customs">customs</option>
          <option value="warehousing">warehousing</option>
          <option value="other">other</option>
        </select>
      </label>
      <label className="flex flex-col text-sm text-neutral-700">
        Source
        <select name="sourceType" required defaultValue="vendor" className="rounded border border-neutral-300 px-2 py-1">
          <option value="vendor">vendor</option>
          <option value="internal">internal</option>
        </select>
      </label>
      <label className="flex flex-col text-sm text-neutral-700">
        Vendor
        <select name="vendorId" className="rounded border border-neutral-300 px-2 py-1">
          <option value="">—</option>
          {vendors.map((vendor) => (
            <option key={vendor.id} value={vendor.id}>
              {vendor.name}
            </option>
          ))}
        </select>
      </label>
      <label className="flex flex-col text-sm text-neutral-700">
        Quantity
        <input type="number" name="quantity" required min={0.0001} step="any" defaultValue={1} className="w-24 rounded border border-neutral-300 px-2 py-1" />
      </label>
      <label className="flex flex-col text-sm text-neutral-700">
        UOM
        <input type="text" name="uom" className="w-24 rounded border border-neutral-300 px-2 py-1" />
      </label>
      <label className="flex flex-col text-sm text-neutral-700">
        Rate
        <input type="number" name="rate" required min={0} step="any" className="w-32 rounded border border-neutral-300 px-2 py-1" />
      </label>
      <label className="flex flex-col text-sm text-neutral-700">
        Minimum
        <input type="number" name="minimumCharge" min={0} step="any" className="w-32 rounded border border-neutral-300 px-2 py-1" />
      </label>
      <label className="flex flex-col text-sm text-neutral-700">
        Surcharge
        <input type="number" name="surcharge" min={0} step="any" defaultValue={0} className="w-24 rounded border border-neutral-300 px-2 py-1" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
        Add component
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function SubmitForm({ submitAction }: { readonly submitAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(submitAction, INITIAL_STATE);
  return (
    <form action={formAction}>
      <Button type="submit" loading={pending} loadingLabel="Submitting…">
        Submit for approval
      </Button>
      {state.error ? (
        <p role="alert" className="mt-1 text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function DecideForm({ decideAction }: { readonly decideAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(decideAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <label className="flex flex-col text-sm text-neutral-700">
        Reason (required to reject)
        <input type="text" name="reason" className="rounded border border-neutral-300 px-2 py-1" />
      </label>
      <Button type="submit" name="decision" value="approved" loading={pending} loadingLabel="Saving…">
        Approve
      </Button>
      <Button type="submit" name="decision" value="rejected" loading={pending} loadingLabel="Saving…" variant="destructive">
        Reject
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function AdjustForm({ adjustAction }: { readonly adjustAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(adjustAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 border-t border-neutral-200 pt-2" noValidate>
      <label className="flex flex-col text-sm text-neutral-700">
        Adjustment reason
        <input type="text" name="adjustmentReason" required className="rounded border border-neutral-300 px-2 py-1" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Starting…">
        Adjust (new version)
      </Button>
      {state.error ? (
        <p role="alert" className="w-full text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
