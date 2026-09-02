"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Select } from "../../../../../../components/forms/select.tsx";
import { Textarea } from "../../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { ShipmentOrderFormState } from "./actions.ts";
import { EXCEPTION_TYPES, EXCEPTION_SEVERITIES } from "../../../../../../server/contracts/exception-escalation/exception-escalation.ts";

const INITIAL_STATE: ShipmentOrderFormState = { error: null };

/** Manual exception intake (OPS-174, Prompt 174 §15) -- source is always "manual" for this internal, user-driven form. */
export function ReportExceptionForm({ action }: { action: (prevState: ShipmentOrderFormState, formData: FormData) => Promise<ShipmentOrderFormState> }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);
  const describedBy = state.error ? "report-exception-error" : undefined;

  return (
    <form action={formAction} className="flex flex-col gap-3" noValidate>
      <div className="grid grid-cols-2 gap-3">
        <FormField id="type" label="Type">
          <Select id="type" name="type" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="" disabled>
              Select a type…
            </option>
            {EXCEPTION_TYPES.map((type) => (
              <option key={type} value={type}>
                {type}
              </option>
            ))}
          </Select>
        </FormField>
        <FormField id="severity" label="Severity">
          <Select id="severity" name="severity" required defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
            <option value="" disabled>
              Select a severity…
            </option>
            {EXCEPTION_SEVERITIES.map((severity) => (
              <option key={severity} value={severity}>
                {severity}
              </option>
            ))}
          </Select>
        </FormField>
        <div className="col-span-2">
          <FormField id="description" label="Description">
            <Textarea id="description" name="description" required rows={2} invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>
      </div>

      {state.error ? <ValidationMessage id="report-exception-error">{state.error}</ValidationMessage> : null}

      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Reporting…" className="w-fit">
        Report exception
      </Button>
    </form>
  );
}
