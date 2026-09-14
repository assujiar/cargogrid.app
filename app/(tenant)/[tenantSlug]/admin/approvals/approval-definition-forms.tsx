"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Textarea } from "../../../../../components/forms/textarea.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { ApprovalDefinitionActionState } from "./actions.ts";

const INITIAL_STATE: ApprovalDefinitionActionState = { error: null };

type BoundAction = (prevState: ApprovalDefinitionActionState, formData: FormData) => Promise<ApprovalDefinitionActionState>;

const EXAMPLE_ITEMS_JSON = JSON.stringify(
  {
    pattern: "sequential",
    allow_self_approval: false,
    steps: [
      { step_order: 1, approver_type: "role", role_id: "<role-uuid-from-the-table-below>", required_approvals: 1 },
      { step_order: 2, approver_type: "role", role_id: "<role-uuid-from-the-table-below>", required_approvals: 1 },
    ],
  },
  null,
  2,
);

export function PublishApprovalDefinitionForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <FormField
        id="itemsJson"
        label="Definition (JSON)"
        helpText={`One object with "pattern" (sequential/parallel/threshold), "steps" (each with step_order, approver_type "role" or "specific_user", role_id or specific_user_id, and required_approvals), an optional "threshold_required_steps" (required when pattern is "threshold"), and an optional "allow_self_approval".`}
        error={state.error ?? undefined}
      >
        <Textarea id="itemsJson" name="itemsJson" rows={12} defaultValue={EXAMPLE_ITEMS_JSON} className="font-mono text-xs" invalid={Boolean(state.error)} />
      </FormField>
      <Button type="submit" loading={pending} loadingLabel="Publishing…" className="w-fit">
        Publish approval definition
      </Button>
    </form>
  );
}

export function RollbackApprovalDefinitionForm({ action }: { action: BoundAction }) {
  const [state, formAction, pending] = useActionState(action, INITIAL_STATE);

  return (
    <form action={formAction} className="flex flex-col gap-2" noValidate>
      <FormField id="rollback-reason" label="Reason (required)">
        <Input id="rollback-reason" name="reason" type="text" required invalid={Boolean(state.error)} />
      </FormField>
      {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Rolling back…" className="w-fit">
        Roll back to this version
      </Button>
    </form>
  );
}
