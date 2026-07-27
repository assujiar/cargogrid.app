"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import { EXCEPTION_TYPES, EXCEPTION_SEVERITIES } from "../../../../../../server/contracts/exception-escalation/exception-escalation.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/** Manual exception intake (OPS-174, Prompt 174 §15) -- source is always "manual" for this internal, user-driven form. */
export function ReportExceptionForm({ action }: { action: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="type" className="text-sm font-medium text-neutral-700">
            Type
          </label>
          <select id="type" name="type" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" defaultValue="">
            <option value="" disabled>
              Select a type…
            </option>
            {EXCEPTION_TYPES.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="severity" className="text-sm font-medium text-neutral-700">
            Severity
          </label>
          <select id="severity" name="severity" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" defaultValue="">
            <option value="" disabled>
              Select a severity…
            </option>
            {EXCEPTION_SEVERITIES.map((severity) => (
              <option key={severity} value={severity}>
                {severity}
              </option>
            ))}
          </select>
        </div>
        <div className="col-span-2 flex flex-col gap-1">
          <label htmlFor="description" className="text-sm font-medium text-neutral-700">
            Description
          </label>
          <textarea id="description" name="description" required rows={2} className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reporting…" className="w-fit">
        Report exception
      </Button>
    </form>
  );
}
