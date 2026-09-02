"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
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
  const describedBy = state.error ? "ingest-milestone-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="grid grid-cols-2 gap-3">
        <FormField id="milestoneCode" label="Milestone">
          <Select id="milestoneCode" name="milestoneCode" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="" disabled>
              Select a milestone…
            </option>
            {milestoneCodes.map((code) => (
              <option key={code.code} value={code.code}>
                {code.name}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="eventTime" label="Occurred at">
          <Input id="eventTime" name="eventTime" type="datetime-local" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="locationLabel" label="Location (optional)">
          <Input id="locationLabel" name="locationLabel" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="correctsEventId" label="Corrects event ID (optional)">
          <Input id="correctsEventId" name="correctsEventId" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <div className="col-span-2">
          <FormField id="reason" label="Reason (required only for a correction)">
            <Input id="reason" name="reason" type="text" invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage id="ingest-milestone-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…" className="w-fit">
        Record milestone event
      </Button>
    </form>
  );
}
