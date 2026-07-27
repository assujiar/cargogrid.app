"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
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
      <div className="flex flex-col gap-1">
        <label htmlFor="newMode" className="text-sm font-medium text-neutral-700">
          New mode
        </label>
        <select id="newMode" name="newMode" className="w-48 rounded-md border border-neutral-300 px-3 py-2 text-sm" defaultValue={currentMode}>
          {SHIPMENT_MODE_PROFILE_MODES.map((mode) => (
            <option key={mode} value={mode}>
              {mode}
            </option>
          ))}
        </select>
      </div>
      <p className="text-xs text-neutral-500">Changing mode deletes the existing mode profile -- a new one must be set afterward.</p>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Changing…" className="w-fit">
        Change mode
      </Button>
    </form>
  );
}
