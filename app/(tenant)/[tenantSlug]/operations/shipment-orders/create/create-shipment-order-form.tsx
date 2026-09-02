"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { FormSection } from "../../../../../../components/forms/form-section.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { NumberInput } from "../../../../../../components/forms/number-input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { CreateShipmentOrderState } from "./actions.ts";
import { SHIPMENT_MODES, type ShipmentMode } from "../../../../../../server/contracts/shipment-order/shipment-order.ts";

const INITIAL_STATE: CreateShipmentOrderState = { error: null };

/**
 * The one atomic, idempotent creation action (OPS-169). basisQuantity/basisWeightKg/
 * basisVolumeCbm are only meaningful -- and only shown -- on the first Shipment Order
 * for a Job Order (`isFirstShipment`); a split shipment shows a required reason field
 * instead, matching the split-reason-required rule the database itself enforces.
 */
export function CreateShipmentOrderForm({
  action,
  isFirstShipment,
}: {
  action: (
    serviceType: string,
    mode: ShipmentMode,
    origin: string,
    destination: string,
    plannedPickupAt: string,
    plannedDeliveryAt: string,
    allocatedQuantity: string,
    allocatedWeightKg: string,
    allocatedVolumeCbm: string,
    basisQuantity: string,
    basisWeightKg: string,
    basisVolumeCbm: string,
    splitReason: string,
    prevState: CreateShipmentOrderState,
    formData: FormData,
  ) => Promise<CreateShipmentOrderState>;
  isFirstShipment: boolean;
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: CreateShipmentOrderState, formData: FormData) => {
      const field = (name: string) => String(formData.get(name) ?? "");
      return action(
        field("serviceType"),
        field("mode") as ShipmentMode,
        field("origin"),
        field("destination"),
        field("plannedPickupAt"),
        field("plannedDeliveryAt"),
        field("allocatedQuantity"),
        field("allocatedWeightKg"),
        field("allocatedVolumeCbm"),
        field("basisQuantity"),
        field("basisWeightKg"),
        field("basisVolumeCbm"),
        field("splitReason"),
        prevState,
        formData,
      );
    },
    INITIAL_STATE,
  );

  const invalid = Boolean(state.error);
  const describedBy = state.error ? "create-shipment-order-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="grid grid-cols-2 gap-3">
        <FormField id="serviceType" label="Service type">
          <Input id="serviceType" name="serviceType" type="text" required defaultValue="ocean_freight" invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="mode" label="Mode">
          <Select id="mode" name="mode" defaultValue={SHIPMENT_MODES[2]} invalid={invalid} aria-describedby={describedBy}>
            {SHIPMENT_MODES.map((mode) => (
              <option key={mode} value={mode}>
                {mode}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="origin" label="Origin">
          <Input id="origin" name="origin" type="text" required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="destination" label="Destination">
          <Input id="destination" name="destination" type="text" required invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="plannedPickupAt" label="Planned pickup">
          <Input id="plannedPickupAt" name="plannedPickupAt" type="datetime-local" invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="plannedDeliveryAt" label="Planned delivery">
          <Input id="plannedDeliveryAt" name="plannedDeliveryAt" type="datetime-local" invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="allocatedQuantity" label="Allocated quantity">
          <NumberInput id="allocatedQuantity" name="allocatedQuantity" step="any" invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="allocatedWeightKg" label="Allocated weight (kg)">
          <NumberInput id="allocatedWeightKg" name="allocatedWeightKg" step="any" invalid={invalid} aria-describedby={describedBy} />
        </FormField>
        <FormField id="allocatedVolumeCbm" label="Allocated volume (cbm)">
          <NumberInput id="allocatedVolumeCbm" name="allocatedVolumeCbm" step="any" invalid={invalid} aria-describedby={describedBy} />
        </FormField>
      </div>

      {isFirstShipment ? (
        <div className="rounded-md border border-neutral-200 p-3">
          <FormSection
            title="Job Order allocation basis"
            description="This is the first Shipment Order for this Job Order -- the totals below declare the Job Order's own governed allocation basis for every future split. Leave a dimension blank to leave it advisory-only (never enforced)."
          >
            <div className="grid grid-cols-3 gap-3">
              <FormField id="basisQuantity" label="Total quantity">
                <NumberInput id="basisQuantity" name="basisQuantity" step="any" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="basisWeightKg" label="Total weight (kg)">
                <NumberInput id="basisWeightKg" name="basisWeightKg" step="any" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
              <FormField id="basisVolumeCbm" label="Total volume (cbm)">
                <NumberInput id="basisVolumeCbm" name="basisVolumeCbm" step="any" invalid={invalid} aria-describedby={describedBy} />
              </FormField>
            </div>
          </FormSection>
        </div>
      ) : (
        <FormField id="splitReason" label="Split reason (required)">
          <Input id="splitReason" name="splitReason" type="text" required minLength={1} invalid={invalid} aria-describedby={describedBy} />
        </FormField>
      )}

      {state.error ? <ValidationMessage id="create-shipment-order-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" loading={pending} loadingLabel="Creating…" className="w-fit">
        Create Shipment Order
      </Button>
    </form>
  );
}
