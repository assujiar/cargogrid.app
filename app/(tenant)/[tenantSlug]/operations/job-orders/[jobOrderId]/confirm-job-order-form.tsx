"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { JobOrderFormState } from "./actions.ts";

const INITIAL_STATE: JobOrderFormState = { error: null };

/** draft -> confirmed, the one gate that makes a Job Order eligible for bounded Shipment Order creation (OPS-169). */
export function ConfirmJobOrderForm({ action }: { action: (prevState: JobOrderFormState, formData: FormData) => Promise<JobOrderFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <Button type="submit" loading={pending} loadingLabel="Confirming…" className="w-fit">
        Confirm Job Order
      </Button>
      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}
