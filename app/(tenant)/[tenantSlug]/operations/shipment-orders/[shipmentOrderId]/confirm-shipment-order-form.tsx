"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/** draft -> confirmed. */
export function ConfirmShipmentOrderForm({ action }: { action: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <Button type="submit" loading={pending} loadingLabel="Confirming…" className="w-fit">
        Confirm Shipment Order
      </Button>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
