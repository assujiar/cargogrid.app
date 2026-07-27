"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import type { MilestoneCode } from "../../../../../../server/contracts/milestone-management/milestone-management.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/** Manual milestone-event capture (OPS-173, Prompt 173 §15) -- source is always "manual" for this internal, user-driven form; api/webhook/import sources are for a future scoped-integration caller, not this UI. */
export function IngestMilestoneEventForm({
  action,
  milestoneCodes,
}: {
  action: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState>;
  milestoneCodes: readonly MilestoneCode[];
}) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="grid grid-cols-2 gap-3">
        <div className="flex flex-col gap-1">
          <label htmlFor="milestoneCode" className="text-sm font-medium text-neutral-700">
            Milestone
          </label>
          <select id="milestoneCode" name="milestoneCode" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" defaultValue="">
            <option value="" disabled>
              Select a milestone…
            </option>
            {milestoneCodes.map((code) => (
              <option key={code.code} value={code.code}>
                {code.name}
              </option>
            ))}
          </select>
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="eventTime" className="text-sm font-medium text-neutral-700">
            Occurred at
          </label>
          <input id="eventTime" name="eventTime" type="datetime-local" required className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="locationLabel" className="text-sm font-medium text-neutral-700">
            Location (optional)
          </label>
          <input id="locationLabel" name="locationLabel" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="flex flex-col gap-1">
          <label htmlFor="correctsEventId" className="text-sm font-medium text-neutral-700">
            Corrects event ID (optional)
          </label>
          <input id="correctsEventId" name="correctsEventId" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
        <div className="col-span-2 flex flex-col gap-1">
          <label htmlFor="reason" className="text-sm font-medium text-neutral-700">
            Reason (required only for a correction)
          </label>
          <input id="reason" name="reason" type="text" className="rounded-md border border-neutral-300 px-3 py-2 text-sm" />
        </div>
      </div>

      {state.error ? (
        <p role="alert" className="text-sm text-danger">
          {state.error}
        </p>
      ) : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…" className="w-fit">
        Record milestone event
      </Button>
    </form>
  );
}
