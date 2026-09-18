"use client";

import { useActionState } from "react";
import { Button } from "../../../../../../components/ui/button.tsx";
import { FormField } from "../../../../../../components/forms/form-field.tsx";
import { Input } from "../../../../../../components/forms/input.tsx";
import { ValidationMessage } from "../../../../../../components/forms/validation-message.tsx";
import type { CustomerPortalAccessFormState } from "./customer-portal-actions.ts";

const INITIAL_STATE: CustomerPortalAccessFormState = { error: null, success: false };

/** CG-AUDIT-2026-09-02 A2b: seeds the first account_admin on this account's own customer portal, once -- every subsequent member is invited self-service from customer-portal-users/ by that account_admin, never through this form again. */
export function CustomerPortalAccessPanel({
  grantAction,
}: {
  grantAction: (prevState: CustomerPortalAccessFormState, formData: FormData) => Promise<CustomerPortalAccessFormState>;
}) {
  const [state, formAction, pending] = useActionState(grantAction, INITIAL_STATE);
  const errorId = "customer-portal-access-error";
  const describedBy = state.error ? errorId : undefined;

  return (
    <div className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Customer portal access</h2>
        <p className="text-xs text-neutral-500">Grant the first account admin on this account&apos;s own customer portal. The customer must already have a CargoGrid identity -- ask them for their account ID, or invite one first.</p>
      </div>
      <form action={formAction} className="flex flex-col gap-2 sm:flex-row sm:items-end">
        <div className="flex-1">
          <FormField id="grant-cpam-auth-user-id" label="Customer's CargoGrid account ID">
            <Input id="grant-cpam-auth-user-id" name="authUserId" placeholder="00000000-0000-0000-0000-000000000000" aria-describedby={describedBy} />
          </FormField>
        </div>
        <Button type="submit" loading={pending} loadingLabel="Granting…">
          Grant portal access
        </Button>
      </form>
      {state.error ? <ValidationMessage id={errorId}>{state.error}</ValidationMessage> : null}
      {state.success ? <p className="text-sm font-medium text-success">Customer portal access granted. The customer can now sign in and manage further members from their own account.</p> : null}
    </div>
  );
}
