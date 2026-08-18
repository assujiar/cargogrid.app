"use client";

/**
 * Customer User Management panel (CPL-315, CG-S13-CPL-017). Invite/role-
 * change/revoke/pending-invites/access-review screens in one account_admin-
 * facing surface, mirroring app/(tenant)/[tenantSlug]/customer-profile/
 * customer-profile-panel.tsx's own multi-form-per-row shape (each row-level
 * form is its own independent useActionState instance sharing one bound
 * Server Action).
 *
 * High-risk actions (role change, suspend, revoke) carry a client-side
 * confirm() step, mirroring app/(tenant)/[tenantSlug]/hris/employees/
 * [masterRecordId]/employee-detail-panel.tsx's own established
 * `confirmReason` pattern -- a UX safeguard against an accidental click,
 * never claimed as an MFA/step-up/RPD-023 control (none exists anywhere in
 * this repository; see actions.ts's own header and docs/build-log/phase-08/
 * CPL-315.md for the full, disclosed residual gap).
 */

import { useActionState } from "react";
import { Button, type ButtonVariant } from "../../../../components/ui/button.tsx";
import { StatusBadge, type StatusTone } from "../../../../components/ui/status-badge.tsx";
import { EmptyState } from "../../../../components/ui/empty-state.tsx";
import type { CustomerPortalUsersActionState } from "./actions.ts";
import type { CustomerPortalAccountMembership } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";
import { CUSTOMER_PORTAL_ACCESS_REVIEW_OUTCOME_LABELS, type CustomerPortalAccessReviewMembershipRow } from "../../../../server/contracts/customer-portal-user-management/customer-portal-user-management.ts";

const INITIAL_STATE: CustomerPortalUsersActionState = { error: null };

type BoundAction = (prevState: CustomerPortalUsersActionState, formData: FormData) => Promise<CustomerPortalUsersActionState>;

const STATUS_TONE: Record<CustomerPortalAccountMembership["status"], StatusTone> = {
  invited: "info",
  active: "success",
  suspended: "warning",
  revoked: "danger",
};

const STATUS_LABEL: Record<CustomerPortalAccountMembership["status"], string> = {
  invited: "Invited (pending)",
  active: "Active",
  suspended: "Suspended",
  revoked: "Revoked",
};

const ROLE_LABEL: Record<CustomerPortalAccountMembership["role"], string> = {
  account_admin: "Account admin",
  member: "Member",
};

function InviteForm({ inviteAction }: { inviteAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(inviteAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4 sm:flex-row sm:items-end">
      <label className="flex-1 text-xs font-medium text-neutral-500">
        User&apos;s CargoGrid account ID
        <input name="authUserId" placeholder="00000000-0000-0000-0000-000000000000" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm" />
      </label>
      <label className="text-xs font-medium text-neutral-500">
        Role
        <select name="role" defaultValue="member" className="mt-1 w-full rounded border border-neutral-300 p-2 text-sm">
          <option value="member">Member</option>
          <option value="account_admin">Account admin</option>
        </select>
      </label>
      <Button type="submit" loading={pending} loadingLabel="Inviting…">
        Invite
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:basis-full">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function RoleChangeForm({ membership, roleAction }: { membership: CustomerPortalAccountMembership; roleAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(roleAction, INITIAL_STATE);
  const nextRole = membership.role === "account_admin" ? "member" : "account_admin";
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="membershipId" value={membership.id} />
      <input type="hidden" name="expectedVersion" value={membership.recordVersion} />
      <input type="hidden" name="newRole" value={nextRole} />
      <Button
        type="submit"
        variant="secondary"
        loading={pending}
        loadingLabel="Updating…"
        onClick={(e) => {
          if (!confirm(`Change this member's role to "${ROLE_LABEL[nextRole]}"?`)) e.preventDefault();
        }}
      >
        Make {ROLE_LABEL[nextRole]}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function StatusChangeForm({
  membership,
  toStatus,
  label,
  variant,
  needsReason,
  statusAction,
}: {
  membership: CustomerPortalAccountMembership;
  toStatus: "active" | "suspended" | "revoked";
  label: string;
  variant: ButtonVariant;
  needsReason: boolean;
  statusAction: BoundAction;
}) {
  const [state, formAction, pending] = useActionState(statusAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-1">
      <input type="hidden" name="membershipId" value={membership.id} />
      <input type="hidden" name="expectedVersion" value={membership.recordVersion} />
      <input type="hidden" name="toStatus" value={toStatus} />
      {needsReason ? <input name="reason" placeholder="Reason (required)" className="rounded border border-neutral-300 p-1 text-xs" /> : null}
      <Button
        type="submit"
        variant={variant}
        loading={pending}
        loadingLabel="Working…"
        onClick={(e) => {
          if (!confirm(`${label} this member's access?`)) e.preventDefault();
        }}
      >
        {label}
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function MembershipRow({ membership, roleAction, statusAction }: { membership: CustomerPortalAccountMembership; roleAction: BoundAction; statusAction: BoundAction }) {
  return (
    <tr className="border-t border-neutral-100 align-top">
      <td className="p-2 text-xs text-neutral-700">{membership.authUserId}</td>
      <td className="p-2 text-sm">
        <StatusBadge tone={membership.role === "account_admin" ? "info" : "neutral"} label={ROLE_LABEL[membership.role]} />
      </td>
      <td className="p-2 text-sm">
        <StatusBadge tone={STATUS_TONE[membership.status]} label={STATUS_LABEL[membership.status]} />
        {membership.status === "suspended" && membership.suspendedReason ? <p className="mt-1 max-w-xs text-xs text-neutral-400">{membership.suspendedReason}</p> : null}
        {membership.status === "revoked" && membership.revokedReason ? <p className="mt-1 max-w-xs text-xs text-neutral-400">{membership.revokedReason}</p> : null}
      </td>
      <td className="p-2 text-xs text-neutral-500">{new Date(membership.status === "invited" ? (membership.invitedAt ?? membership.grantedAt) : membership.grantedAt).toLocaleDateString()}</td>
      <td className="p-2">
        <div className="flex flex-col gap-2">
          {membership.status === "active" ? (
            <>
              <RoleChangeForm membership={membership} roleAction={roleAction} />
              <StatusChangeForm membership={membership} toStatus="suspended" label="Suspend" variant="secondary" needsReason statusAction={statusAction} />
              <StatusChangeForm membership={membership} toStatus="revoked" label="Revoke" variant="destructive" needsReason statusAction={statusAction} />
            </>
          ) : null}
          {membership.status === "suspended" ? (
            <>
              <StatusChangeForm membership={membership} toStatus="active" label="Reactivate" variant="secondary" needsReason={false} statusAction={statusAction} />
              <StatusChangeForm membership={membership} toStatus="revoked" label="Revoke" variant="destructive" needsReason statusAction={statusAction} />
            </>
          ) : null}
          {membership.status === "invited" ? <StatusChangeForm membership={membership} toStatus="revoked" label="Cancel invite" variant="destructive" needsReason statusAction={statusAction} /> : null}
          {membership.status === "revoked" ? <span className="text-xs text-neutral-400">No further action -- revoked is permanent</span> : null}
        </div>
      </td>
    </tr>
  );
}

function MembersTable({ memberships, roleAction, statusAction }: { memberships: readonly CustomerPortalAccountMembership[]; roleAction: BoundAction; statusAction: BoundAction }) {
  if (memberships.length === 0) {
    return <EmptyState title="No users yet" description="Invite a user above to get started." />;
  }
  return (
    <div className="overflow-x-auto rounded-md border border-neutral-200">
      <table className="w-full border-collapse">
        <thead>
          <tr className="text-left text-xs font-medium text-neutral-500">
            <th className="p-2">User</th>
            <th className="p-2">Role</th>
            <th className="p-2">Status</th>
            <th className="p-2">Since</th>
            <th className="p-2">Actions</th>
          </tr>
        </thead>
        <tbody>
          {memberships.map((m) => (
            <MembershipRow key={m.id} membership={m} roleAction={roleAction} statusAction={statusAction} />
          ))}
        </tbody>
      </table>
    </div>
  );
}

function AccessReviewForm({ row, reviewAction }: { row: CustomerPortalAccessReviewMembershipRow; reviewAction: BoundAction }) {
  const [state, formAction, pending] = useActionState(reviewAction, INITIAL_STATE);
  return (
    <form action={formAction} className="flex flex-col gap-2 sm:flex-row sm:items-end sm:gap-2">
      <input type="hidden" name="membershipId" value={row.membershipId} />
      <label className="text-xs font-medium text-neutral-500">
        Outcome
        <select name="reviewOutcome" defaultValue="confirmed_appropriate" className="mt-1 rounded border border-neutral-300 p-1 text-xs">
          {Object.entries(CUSTOMER_PORTAL_ACCESS_REVIEW_OUTCOME_LABELS).map(([value, label]) => (
            <option key={value} value={value}>
              {label}
            </option>
          ))}
        </select>
      </label>
      <label className="flex-1 text-xs font-medium text-neutral-500">
        Note (optional)
        <input name="note" className="mt-1 w-full rounded border border-neutral-300 p-1 text-xs" />
      </label>
      <Button type="submit" variant="secondary" loading={pending} loadingLabel="Recording…">
        Record review
      </Button>
      {state.error ? (
        <p role="alert" className="text-xs text-danger sm:basis-full">
          {state.error}
        </p>
      ) : null}
    </form>
  );
}

function AccessReviewSection({ rows }: { rows: readonly { row: CustomerPortalAccessReviewMembershipRow; reviewAction: BoundAction }[] }) {
  return (
    <section aria-label="Access review" className="flex flex-col gap-3 rounded-md border border-neutral-200 p-4">
      <div>
        <h2 className="text-sm font-semibold text-neutral-900">Access review</h2>
        <p className="text-xs text-neutral-500">Periodically confirm every active member&apos;s access is still appropriate. A review records an attestation -- it does not itself change role or status; use the actions above for that.</p>
      </div>
      {rows.length === 0 ? (
        <EmptyState title="No active users to review" description="Active members will appear here once your account has some." />
      ) : (
        <div className="flex flex-col gap-3">
          {rows.map(({ row, reviewAction }) => (
            <div key={row.membershipId} className="flex flex-col gap-2 rounded border border-neutral-100 p-3">
              <div className="flex flex-wrap items-center gap-2 text-xs text-neutral-700">
                <span className="font-medium">{row.authUserId}</span>
                <StatusBadge tone={row.role === "account_admin" ? "info" : "neutral"} label={ROLE_LABEL[row.role]} />
                {row.lastReviewedAt ? (
                  <span className="text-neutral-400">
                    Last reviewed {new Date(row.lastReviewedAt).toLocaleDateString()}
                    {row.lastReviewOutcome ? ` -- ${CUSTOMER_PORTAL_ACCESS_REVIEW_OUTCOME_LABELS[row.lastReviewOutcome]}` : ""}
                    {row.lastReviewNote ? `: ${row.lastReviewNote}` : ""}
                  </span>
                ) : (
                  <span className="text-neutral-400">Never reviewed</span>
                )}
              </div>
              <AccessReviewForm row={row} reviewAction={reviewAction} />
            </div>
          ))}
        </div>
      )}
    </section>
  );
}

export function CustomerPortalUsersPanel({
  memberships,
  reviewRows,
  inviteAction,
  roleAction,
  statusAction,
}: {
  memberships: readonly CustomerPortalAccountMembership[];
  reviewRows: readonly { row: CustomerPortalAccessReviewMembershipRow; reviewAction: BoundAction }[];
  inviteAction: BoundAction;
  roleAction: BoundAction;
  statusAction: BoundAction;
}) {
  return (
    <div className="flex flex-col gap-4">
      <InviteForm inviteAction={inviteAction} />
      <MembersTable memberships={memberships} roleAction={roleAction} statusAction={statusAction} />
      <AccessReviewSection rows={reviewRows} />
    </div>
  );
}
