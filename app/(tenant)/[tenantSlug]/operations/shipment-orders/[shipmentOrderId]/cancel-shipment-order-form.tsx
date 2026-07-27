"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/** draft/confirmed -> cancelled, mandatory reason. */
export function CancelShipmentOrderForm({
  action,
}: {
  action: (reason: string, prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [state, formAction, pending] = useActionState(
    async (prevState: ShipmentOrderFormState, formData: FormData) => action(String(formData.get("reason") ?? "").trim(), prevState, formData),
    INITIAL_STATE,
  );

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <div className="flex flex-col gap-1">
        <label htmlFor="reason" className="text-sm font-medium text-neutral-700">
          Cancellation reason (required)
        </label>
        <input id="reason" name="reason" type="text" required minLength={1} className="w-96 rounded-md border border-neutral-300 px-3 py-2 text-sm" />
      </div>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Cancelling…" className="w-fit">
        Cancel Shipment Order
      </Button>
    </form>
  );
}
