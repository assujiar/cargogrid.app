"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import { SHIPMENT_MODE_PROFILE_MODES, type ShipmentModeProfileMode } from "../../../../../../server/contracts/shipment-mode-baseline/shipment-mode-baseline.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/** draft-only (Prompt 171 §22) -- reconciles (deletes) the prior incompatible profile server-side. */
export function ChangeModeForm({
  action,
  currentMode,
}: {
  action: (newMode: ShipmentModeProfileMode, prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  currentMode: ShipmentModeProfileMode;
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: ShipmentOrderFormState, formData: FormData) => action(String(formData.get("newMode")) as ShipmentModeProfileMode, prevState, formData),
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <FormField id="newMode" label="New mode">
        <Select
          id="newMode"
          name="newMode"
          className="w-48"
          defaultValue={currentMode}
          invalid={Boolean(state.error)}
          aria-describedby={state.error ? "change-mode-error" : undefined}
        >
          {SHIPMENT_MODE_PROFILE_MODES.map((mode) => (
            <option key={mode} value={mode}>
              {mode}
            </option>
          ))}
        </Select>
      </FormField>
      <p className="text-xs text-neutral-500">Changing mode deletes the existing mode profile -- a new one must be set afterward.</p>
      {state.error ? <ValidationMessage id="change-mode-error">{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Changing…" className="w-fit">
        Change mode
      </Button>
    </form>
  );
}
