"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import type { ShipmentModeProfile, ShipmentModeProfileMode } from "../../../../../../server/contracts/shipment-mode-baseline/shipment-mode-baseline.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/**
 * Conditional mode-specific fields (OPS-171, Prompt 171 §15) -- only the fields
 * relevant to the shipment's own current mode are ever rendered; irrelevant fields
 * are hidden, never deleted (the shipment's mode itself is unaffected by this form,
 * only its own profile detail values).
 */
export function ModeProfileForm({
  action,
  mode,
  existingProfile,
}: {
  action: (fields: Record<string, string>, prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  mode: ShipmentModeProfileMode;
  existingProfile: ShipmentModeProfile | null;
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: ShipmentOrderFormState, formData: FormData) => {
      const fields: Record<string, string> = {};
      for (const [key, value] of formData.entries()) {
        fields[key] = String(value);
      }
      return action(fields, prevState, formData);
    },
    INITIAL_STATE,
  );

  const land = existingProfile?.mode === "land" ? existingProfile : null;
  const air = existingProfile?.mode === "air" ? existingProfile : null;
  const sea = existingProfile?.mode === "sea" ? existingProfile : null;
  const invalid = Boolean(state.error);
  const describedBy = state.error ? "mode-profile-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      {mode === "land" ? (
        <div className="grid grid-cols-2 gap-3">
          <Field id="vehicleRef" label="Vehicle reference" defaultValue={land?.vehicleRef} invalid={invalid} describedBy={describedBy} />
          <Field id="vendorRef" label="Vendor reference" defaultValue={land?.vendorRef} invalid={invalid} describedBy={describedBy} />
          <Field id="pickupAddress" label="Pickup address" defaultValue={land?.pickupAddress} invalid={invalid} describedBy={describedBy} />
          <Field id="deliveryAddress" label="Delivery address" defaultValue={land?.deliveryAddress} invalid={invalid} describedBy={describedBy} />
        </div>
      ) : null}

      {mode === "air" ? (
        <div className="grid grid-cols-2 gap-3">
          <Field id="awbNumber" label="AWB number" defaultValue={air?.awbNumber} invalid={invalid} describedBy={describedBy} />
          <Field id="flightNumber" label="Flight number" defaultValue={air?.flightNumber} invalid={invalid} describedBy={describedBy} />
          <Field id="originAirport" label="Origin airport" defaultValue={air?.originAirport} invalid={invalid} describedBy={describedBy} />
          <Field id="destinationAirport" label="Destination airport" defaultValue={air?.destinationAirport} invalid={invalid} describedBy={describedBy} />
        </div>
      ) : null}

      {mode === "sea" ? (
        <div className="grid grid-cols-2 gap-3">
          <Field id="blNumber" label="B/L number" defaultValue={sea?.blNumber} invalid={invalid} describedBy={describedBy} />
          <Field id="bookingNumber" label="Booking number" defaultValue={sea?.bookingNumber} invalid={invalid} describedBy={describedBy} />
          <Field id="vesselName" label="Vessel name" defaultValue={sea?.vesselName} invalid={invalid} describedBy={describedBy} />
          <Field id="originPort" label="Origin port" defaultValue={sea?.originPort} invalid={invalid} describedBy={describedBy} />
          <Field id="destinationPort" label="Destination port" defaultValue={sea?.destinationPort} invalid={invalid} describedBy={describedBy} />
          <Field
            id="containerNumber"
            label="Container number (optional)"
            defaultValue={sea?.containerNumber ?? undefined}
            required={false}
            invalid={invalid}
            describedBy={describedBy}
          />
          <Field
            id="containerType"
            label="Container type (optional)"
            defaultValue={sea?.containerType ?? undefined}
            required={false}
            invalid={invalid}
            describedBy={describedBy}
          />
        </div>
      ) : null}

      {state.error ? <ValidationMessage id="mode-profile-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Saving…" className="w-fit">
        {existingProfile ? "Update mode profile" : "Set mode profile"}
      </Button>
    </form>
  );
}

function Field({
  id,
  label,
  defaultValue,
  required = true,
  invalid = false,
  describedBy,
}: {
  id: string;
  label: string;
  defaultValue?: string;
  required?: boolean;
  invalid?: boolean;
  describedBy?: string | undefined;
}) {
  return (
    <FormField id={id} label={label}>
      <Input id={id} name={id} type="text" required={required} defaultValue={defaultValue} invalid={invalid} aria-describedby={describedBy} />
    </FormField>
  );
}
