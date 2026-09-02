"use client";

import { useActionState, useId } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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
        <FormField id="actual-cost-currency" label="Currency">
          <Input
            id="actual-cost-currency"
            type="text"
            name="currency"
            required
            defaultValue="IDR"
            className="w-20"
            invalid={Boolean(createState.error)}
            aria-describedby={createState.error ? "actual-cost-create-error" : undefined}
          />
        </FormField>
        <FormField id="actual-cost-estimated-amount" label="Estimated amount (optional)">
          <NumberInput
            id="actual-cost-estimated-amount"
            name="estimatedAmount"
            min={0}
            step="any"
            className="w-40"
            invalid={Boolean(createState.error)}
            aria-describedby={createState.error ? "actual-cost-create-error" : undefined}
          />
        </FormField>
        <Button type="submit" loading={createPending} loadingLabel="Starting…">
          Start actual cost
        </Button>
        {createState.error ? (
          <div className="mt-1">
            <ValidationMessage id="actual-cost-create-error">{createState.error}</ValidationMessage>
          </div>
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
  // This component renders once per cost component, so the error id must be row-unique.
  const rowId = useId();
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
      {removeState.error ? <ValidationMessage id={`${rowId}-remove-error`}>{removeState.error}</ValidationMessage> : null}
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
  const describedBy = state.error ? "add-component-error" : undefined;
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 border-t border-neutral-200 pt-2" noValidate>
      <FormField id="component-category" label="Category">
        <Select id="component-category" name="category" required defaultValue="freight" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="freight">freight</option>
          <option value="trucking">trucking</option>
          <option value="fuel_surcharge">fuel_surcharge</option>
          <option value="handling">handling</option>
          <option value="customs">customs</option>
          <option value="warehousing">warehousing</option>
          <option value="other">other</option>
        </Select>
      </FormField>
      <FormField id="component-source-type" label="Source">
        <Select id="component-source-type" name="sourceType" required defaultValue="vendor" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="vendor">vendor</option>
          <option value="internal">internal</option>
        </Select>
      </FormField>
      <FormField id="component-vendor-id" label="Vendor">
        <Select id="component-vendor-id" name="vendorId" invalid={Boolean(state.error)} aria-describedby={describedBy}>
          <option value="">—</option>
          {vendors.map((vendor) => (
            <option key={vendor.id} value={vendor.id}>
              {vendor.name}
            </option>
          ))}
        </Select>
      </FormField>
      <FormField id="component-quantity" label="Quantity">
        <NumberInput id="component-quantity" name="quantity" required min={0.0001} step="any" defaultValue={1} className="w-24" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="component-uom" label="UOM">
        <Input id="component-uom" type="text" name="uom" className="w-24" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="component-rate" label="Rate">
        <NumberInput id="component-rate" name="rate" required min={0} step="any" className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="component-minimum-charge" label="Minimum">
        <Input type="number" inputMode="decimal" id="component-minimum-charge" name="minimumCharge" min={0} step="any" className="w-32" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <FormField id="component-surcharge" label="Surcharge">
        <Input type="number" inputMode="decimal" id="component-surcharge" name="surcharge" min={0} step="any" defaultValue={0} className="w-24" invalid={Boolean(state.error)} aria-describedby={describedBy} />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Adding…">
        Add component
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="add-component-error">{state.error}</ValidationMessage>
        </div>
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
        <div className="mt-1">
          <ValidationMessage id="actual-cost-submit-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function DecideForm({ decideAction }: { readonly decideAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(decideAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2" noValidate>
      <FormField id="actual-cost-decide-reason" label="Reason (required to reject)">
        <Input
          id="actual-cost-decide-reason"
          type="text"
          name="reason"
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? "actual-cost-decide-error" : undefined}
        />
      </FormField>
      <Button type="submit" name="decision" value="approved" loading={pending} loadingLabel="Saving…">
        Approve
      </Button>
      <Button type="submit" name="decision" value="rejected" loading={pending} loadingLabel="Saving…" variant="destructive">
        Reject
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="actual-cost-decide-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}

function AdjustForm({ adjustAction }: { readonly adjustAction: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(adjustAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-wrap items-end gap-2 border-t border-neutral-200 pt-2" noValidate>
      <FormField id="actual-cost-adjustment-reason" label="Adjustment reason">
        <Input
          id="actual-cost-adjustment-reason"
          type="text"
          name="adjustmentReason"
          required
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? "actual-cost-adjust-error" : undefined}
        />
      </FormField>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Starting…">
        Adjust (new version)
      </Button>
      {state.error ? (
        <div className="w-full">
          <ValidationMessage id="actual-cost-adjust-error">{state.error}</ValidationMessage>
        </div>
      ) : null}
    </form>
  );
}
