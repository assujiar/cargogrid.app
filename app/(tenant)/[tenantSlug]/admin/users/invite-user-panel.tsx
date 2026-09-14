"use client";

import { useActionState } from "react";
import { Button } from "../../../../../components/ui/button.tsx";
import { Input } from "../../../../../components/forms/input.tsx";
import { Select } from "../../../../../components/forms/select.tsx";
import { FormField } from "../../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../../components/forms/validation-message.tsx";
import type { InviteUserActionState } from "./actions.ts";
import type { OrgUnitSummary } from "../../../../../server/queries/org-hierarchy.ts";

const INITIAL_STATE: InviteUserActionState = { error: null };

export function InviteUserPanel({
  orgUnits,
  inviteAction,
}: {
  orgUnits: readonly OrgUnitSummary[];
  inviteAction: (prevState: InviteUserActionState, formData: FormData) => Promise<InviteUserActionState>;
}) {
  const [state, formAction, pending] = useActionState(inviteAction, INITIAL_STATE);
  const describedBy = state.error ? "invite-user-error" : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Invite a user</h2>
      <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <FormField id="email" label="Email">
          <Input id="email" name="email" type="email" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="displayName" label="Display name">
          <Input id="displayName" name="displayName" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <div className="sm:col-span-2">
          <FormField id="orgUnitId" label="Org unit (optional)">
            <Select id="orgUnitId" name="orgUnitId" defaultValue="" invalid={Boolean(state.error)} aria-describedby={describedBy}>
              <option value="">No org unit</option>
              {orgUnits.map((unit) => (
                <option key={unit.id} value={unit.id}>
                  {unit.name}
                </option>
              ))}
            </Select>
          </FormField>
        </div>

        {state.error ? (
          <div className="col-span-full">
            <ValidationMessage id="invite-user-error">{state.error}</ValidationMessage>
          </div>
        ) : null}

        <div className="col-span-full">
          <Button type="submit" loading={pending} loadingLabel="Sending invitation…">
            Send invitation
          </Button>
        </div>
      </form>
    </section>
  );
}
