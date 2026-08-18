"use server";

/**
 * Customer User Management Server Actions (CPL-315, CG-S13-CPL-017). Mirrors
 * app/(tenant)/[tenantSlug]/customer-profile/actions.ts's own shape --
 * resolve the portal guard first, forward to the typed mutation wrapper,
 * classify the error into a form-safe message, revalidate the affected
 * route. Every write is scope/authority-gated at the RPC layer itself
 * (app.actor_is_active_customer_portal_account_admin) -- this file never
 * re-derives or trusts a client-supplied authority decision, it only
 * forwards.
 *
 * inviteCustomerPortalUserAction/setCustomerPortalAccountMembershipStatusAction
 * compose CPL-300's own already-VERIFIED app.invite_customer_portal_user /
 * app.set_customer_portal_account_membership_status (server/mutations/
 * customer-portal-scope.ts) -- CPL-300 shipped the RPCs and typed wrappers
 * but deliberately wired no UI caller for them (that migration's own §9:
 * "the full Customer User Management UI is Prompt 315's own chartered
 * scope"). This file is that caller. updateCustomerPortalAccountMembership
 * RoleAction/recordCustomerPortalAccountMembershipAccessReviewAction compose
 * this checkpoint's own new RPCs.
 *
 * RPD-023 (MFA/current-authorization for high-risk changes): no MFA/step-up
 * mechanism exists anywhere in this repository (grep-verified repository-
 * wide, disclosed identically by CPL-300 §9 and this checkpoint's own build
 * log/KNOWN_ISSUES.md entry) -- role-change/suspend/revoke actions below
 * carry a client-side confirm() step (mirrors app/(tenant)/[tenantSlug]/hris/
 * employees/[masterRecordId]/employee-detail-panel.tsx's own established
 * `confirmReason` pattern) as a UX safeguard against an accidental click,
 * NEVER represented as satisfying RPD-023 -- the real authorization
 * boundary is, and remains, the server-side account_admin check every RPC
 * below performs on every call, live, never cached.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCustomerPortalAccessForRequest } from "../../../../lib/portal/resolve-customer-portal-access.server.ts";
import { inviteCustomerPortalUser, setCustomerPortalAccountMembershipStatus, CustomerPortalScopeMutationError } from "../../../../server/mutations/customer-portal-scope.ts";
import { updateCustomerPortalAccountMembershipRole, recordCustomerPortalAccountMembershipAccessReview, CustomerPortalUserManagementMutationError } from "../../../../server/mutations/customer-portal-user-management.ts";
import type { CustomerPortalMembershipRole } from "../../../../server/contracts/customer-portal-scope/customer-portal-scope.ts";
import type { CustomerPortalAccessReviewOutcome } from "../../../../server/contracts/customer-portal-user-management/customer-portal-user-management.ts";

export interface CustomerPortalUsersActionState {
  readonly error: string | null;
}

const OK: CustomerPortalUsersActionState = { error: null };
const NO_ACCESS: CustomerPortalUsersActionState = { error: "You don't have access to this organization's customer portal." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveCustomerPortalAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function usersPath(tenantSlug: string, accountId: string): string {
  return `/${tenantSlug}/customer-portal-users?accountId=${accountId}`;
}

function errorMessage(prefix: string, error: unknown): CustomerPortalUsersActionState {
  if (error instanceof CustomerPortalScopeMutationError || error instanceof CustomerPortalUserManagementMutationError) {
    return { error: `${prefix}: ${error.message}` };
  }
  throw error;
}

function orNull(value: FormDataEntryValue | null): string | null {
  const text = String(value ?? "").trim();
  return text.length === 0 ? null : text;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function inviteCustomerPortalUserAction(
  tenantSlug: string,
  accountId: string,
  _prevState: CustomerPortalUsersActionState,
  formData: FormData,
): Promise<CustomerPortalUsersActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const authUserId = orNull(formData.get("authUserId"));
  const role = orNull(formData.get("role"));
  if (!authUserId || !UUID_RE.test(authUserId)) {
    return { error: "Enter the user's CargoGrid account ID (a valid UUID) -- they must already have a CargoGrid identity before they can be invited." };
  }
  if (role !== "account_admin" && role !== "member") {
    return { error: "Choose a role to invite this user as." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await inviteCustomerPortalUser(supabase, {
      tenantId: access.tenant.id,
      accountId,
      authUserId,
      role: role as CustomerPortalMembershipRole,
      actorAuthUserId: access.authUserId,
      invitedBy: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not invite this user", error);
  }
  revalidatePath(usersPath(tenantSlug, accountId));
  return OK;
}

export async function updateCustomerPortalAccountMembershipRoleAction(
  tenantSlug: string,
  accountId: string,
  _prevState: CustomerPortalUsersActionState,
  formData: FormData,
): Promise<CustomerPortalUsersActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const membershipId = orNull(formData.get("membershipId"));
  const newRole = orNull(formData.get("newRole"));
  const expectedVersionRaw = orNull(formData.get("expectedVersion"));
  const expectedVersion = expectedVersionRaw ? Number(expectedVersionRaw) : NaN;
  if (!membershipId || (newRole !== "account_admin" && newRole !== "member") || !Number.isInteger(expectedVersion)) {
    return { error: "This member could not be identified." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateCustomerPortalAccountMembershipRole(supabase, {
      membershipId,
      expectedVersion,
      newRole: newRole as CustomerPortalMembershipRole,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not update this member's role", error);
  }
  revalidatePath(usersPath(tenantSlug, accountId));
  return OK;
}

export async function setCustomerPortalAccountMembershipStatusAction(
  tenantSlug: string,
  accountId: string,
  _prevState: CustomerPortalUsersActionState,
  formData: FormData,
): Promise<CustomerPortalUsersActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const membershipId = orNull(formData.get("membershipId"));
  const toStatus = orNull(formData.get("toStatus"));
  const expectedVersionRaw = orNull(formData.get("expectedVersion"));
  const expectedVersion = expectedVersionRaw ? Number(expectedVersionRaw) : NaN;
  const reason = orNull(formData.get("reason"));
  if (!membershipId || (toStatus !== "active" && toStatus !== "suspended" && toStatus !== "revoked") || !Number.isInteger(expectedVersion)) {
    return { error: "This member could not be identified." };
  }
  if ((toStatus === "suspended" || toStatus === "revoked") && !reason) {
    return { error: "A reason is required to suspend or revoke a member." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await setCustomerPortalAccountMembershipStatus(supabase, {
      membershipId,
      expectedVersion,
      toStatus,
      reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not update this member's status", error);
  }
  revalidatePath(usersPath(tenantSlug, accountId));
  return OK;
}

export async function recordCustomerPortalAccountMembershipAccessReviewAction(
  tenantSlug: string,
  accountId: string,
  idempotencyKey: string,
  _prevState: CustomerPortalUsersActionState,
  formData: FormData,
): Promise<CustomerPortalUsersActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const membershipId = orNull(formData.get("membershipId"));
  const reviewOutcome = orNull(formData.get("reviewOutcome"));
  const note = orNull(formData.get("note"));
  if (!membershipId || (reviewOutcome !== "confirmed_appropriate" && reviewOutcome !== "flagged_for_follow_up")) {
    return { error: "Choose a review outcome for this member." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await recordCustomerPortalAccountMembershipAccessReview(supabase, {
      membershipId,
      reviewOutcome: reviewOutcome as CustomerPortalAccessReviewOutcome,
      note,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    return errorMessage("Could not record this access review", error);
  }
  revalidatePath(usersPath(tenantSlug, accountId));
  return OK;
}
