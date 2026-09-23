"use client";

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { Input } from "../../../../components/forms/input.tsx";
import { Select } from "../../../../components/forms/select.tsx";
import { Checkbox } from "../../../../components/forms/checkbox.tsx";
import { FormField } from "../../../../components/forms/form-field.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import type { SupportAccessActionState } from "./actions.ts";

const INITIAL_STATE: SupportAccessActionState = { error: null };

export function RequestSupportAccessPanel({
  requestAction,
}: {
  requestAction: (prevState: SupportAccessActionState, formData: FormData) => Promise<SupportAccessActionState>;
}) {
  const [state, formAction, pending] = useActionState(requestAction, INITIAL_STATE);
  const describedBy = state.error ? "request-support-access-error" : undefined;

  return (
    <section className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <h2 className="text-sm font-semibold text-neutral-900">Request support access</h2>
      <p className="text-xs text-neutral-600">
        A standard request needs approval from Supreme Admin or the target tenant&apos;s own tenant_admin before it grants
        anything. An emergency request is granted immediately, under your own recorded authority, and must be closed out
        with a post-review note afterward.
      </p>
      <form action={formAction} className="grid grid-cols-1 gap-3 sm:grid-cols-2">
        <FormField id="tenantId" label="Tenant ID" helpText="The tenant's UUID (see the Tenants page).">
          <Input id="tenantId" name="tenantId" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="granteeAuthUserId" label="Grantee auth user ID">
          <Input id="granteeAuthUserId" name="granteeAuthUserId" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="caseId" label="Case ID">
          <Input id="caseId" name="caseId" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="expiryMinutes" label="Expiry (minutes)" helpText="Up to 1440 for a standard request, 120 for emergency.">
          <Input id="expiryMinutes" name="expiryMinutes" type="number" min="1" max="1440" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
        </FormField>
        <FormField id="scope" label="Scope">
          <Select id="scope" name="scope" defaultValue="read_only" invalid={Boolean(state.error)}>
            <option value="read_only">Read only</option>
            <option value="read_write">Read/write</option>
          </Select>
        </FormField>
        <div className="flex items-end">
          <Checkbox id="emergency" name="emergency" label="Emergency (bypasses approval, under my own authority)" />
        </div>
        <div className="col-span-full">
          <FormField id="reason" label="Reason">
            <Input id="reason" name="reason" type="text" required invalid={Boolean(state.error)} aria-describedby={describedBy} />
          </FormField>
        </div>

        {state.error ? (
          <div className="col-span-full">
            <ValidationMessage id="request-support-access-error">{state.error}</ValidationMessage>
          </div>
        ) : null}

        <div className="col-span-full">
          <Button type="submit" loading={pending} loadingLabel="Requesting…">
            Request access
          </Button>
        </div>
      </form>
    </section>
  );
}
