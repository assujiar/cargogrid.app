"use client";

/**
 * Pending customer-portal invite acceptance (CG-AUDIT-2026-09-02 A2b).
 * Rendered from page.tsx's own "forbidden" branch, for an authenticated
 * identity that holds no active customer_user-layer principal yet but does
 * hold one or more real, still-invited app.customer_portal_account_
 * memberships rows -- mirrors customer-portal-users-panel.tsx's own
 * per-row useActionState shape.
 */

import { useActionState } from "react";
import { Button } from "../../../../components/ui/button.tsx";
import { ValidationMessage } from "../../../../components/forms/validation-message.tsx";
import type { CustomerPortalPendingInvite } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";
import type { AcceptCustomerPortalInviteActionState } from "./accept-invite-actions.ts";

const INITIAL_STATE: AcceptCustomerPortalInviteActionState = { error: null };

const ROLE_LABEL: Record<CustomerPortalPendingInvite["role"], string> = {
  account_admin: "Account admin",
  member: "Member",
};

function InviteRow({
  invite,
  acceptAction,
}: {
  invite: CustomerPortalPendingInvite;
  acceptAction: (prevState: AcceptCustomerPortalInviteActionState, formData: FormData) => Promise<AcceptCustomerPortalInviteActionState>;
}) {
  const [state, formAction, pending] = useActionState(acceptAction, INITIAL_STATE);
  return (
    <li className="flex flex-col gap-2 rounded-md border border-neutral-200 p-4">
      <div>
        <p className="text-sm font-medium text-neutral-900">{invite.accountName}</p>
        <p className="text-xs text-neutral-500">Invited as {ROLE_LABEL[invite.role]}</p>
      </div>
      <form action={formAction}>
        <input type="hidden" name="membershipId" value={invite.membershipId} />
        <input type="hidden" name="expectedVersion" value={invite.recordVersion} />
        <Button type="submit" loading={pending} loadingLabel="Accepting…" className="w-fit">
          Accept invite
        </Button>
        {state.error ? <ValidationMessage>{state.error}</ValidationMessage> : null}
      </form>
    </li>
  );
}

export function PendingInvitesPanel({
  invites,
  acceptAction,
}: {
  invites: readonly CustomerPortalPendingInvite[];
  acceptAction: (prevState: AcceptCustomerPortalInviteActionState, formData: FormData) => Promise<AcceptCustomerPortalInviteActionState>;
}) {
  return (
    <div className="flex w-full flex-col gap-3">
      <p className="text-center text-sm text-neutral-600">You have been invited to access the customer portal for the following account{invites.length > 1 ? "s" : ""}:</p>
      <ul className="flex flex-col gap-2">
        {invites.map((invite) => (
          <InviteRow key={invite.membershipId} invite={invite} acceptAction={acceptAction} />
        ))}
      </ul>
    </div>
  );
}
