"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { StatusBadge } from "../../../../../../components/ui/status-badge.tsx";
import type { DispatchReadiness } from "../../../../../../server/contracts/basic-dispatch/basic-dispatch.ts";
import type { ShipmentOrderFormState } from "./actions.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/** OPS-175: readiness display (the same app.evaluate_dispatch_readiness result app.dispatch_shipment_order rechecks at commit time) plus the one Dispatch button, shown only while status = 'assigned'. */
export function DispatchPanel({
  readiness,
  action,
}: {
  readonly readiness: DispatchReadiness;
  readonly action: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <div className="flex flex-col gap-2">
      {readiness.isReady ? (
        <StatusBadge tone="success" label="Ready to dispatch" />
      ) : (
        <div className="flex flex-col gap-1">
          <StatusBadge tone="warning" label="Not ready" />
          <ul className="list-inside list-disc text-sm text-neutral-600">
            {readiness.blockers.map((blocker) => (
              <li key={blocker.code}>{blocker.code}</li>
            ))}
          </ul>
        </div>
      )}
      <form action={formAction} className="flex flex-col gap-2" noValidate>
        <Button type="submit" loading={pending} loadingLabel="Dispatching…" disabled={!readiness.isReady} className="w-fit">
          Dispatch
        </Button>
        {state.error ? (
          <p role="alert" className="text-sm text-danger">
            {state.error}
          </p>
        ) : null}
      </form>
    </div>
  );
}
