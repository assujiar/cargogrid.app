"use server";

/**
 * User invitation Server Action (audit remediation A2;
 * `docs/audit/2026-09-02-independent-launch-readiness-audit.md` finding A2:
 * "No code path anywhere calls admin.createUser, inviteUserByEmail,
 * generateLink or signUp()"). `inviteUser` (`server/mutations/user-lifecycle.ts`,
 * PLT-110) already existed, fully implemented and tested -- but it only
 * creates the `app.users` profile row linking a tenant to an ALREADY-EXISTING
 * Supabase Auth identity (`authUserId` is a required parameter, not
 * generated); nothing anywhere created that identity in the first place.
 * This closes that missing half: `supabase.auth.admin.inviteUserByEmail`
 * (the Auth Admin API, service-role only) creates the `auth.users` row and
 * sends the actual invite email, then `inviteUser` records the tenant
 * membership against the id it returns.
 *
 * `app.invite_user` is granted to `service_role` only (this file's own
 * migration's grants) -- both calls below use the service-role client, the
 * same "explicit actor, service-role execution" pattern every other
 * privileged mutation in this repository already follows (the caller's real
 * identity is authenticated via the RLS-scoped client, then passed
 * explicitly as `p_invited_by`, never inferred from `auth.uid()` inside the
 * privileged function itself).
 *
 * Deliberately does not attempt to reconcile "this email already has an
 * Auth identity" (e.g. a person already invited to a different tenant):
 * `inviteUserByEmail` reports that case as an error, which is surfaced to
 * the admin verbatim rather than guessed at -- there is no `getUserByEmail`
 * in the Admin API to safely look up the existing identity, and a wrong
 * guess here would silently attach the invite to the wrong account.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServiceRoleClient } from "../../../../../lib/supabase/service-role.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { inviteUser, toUserLifecycleRpcClient, UserLifecycleMutationError } from "../../../../../server/mutations/user-lifecycle.ts";

export interface InviteUserActionState {
  readonly error: string | null;
}

const OK: InviteUserActionState = { error: null };
const NO_ACCESS: InviteUserActionState = { error: "You don't have access to invite users to this organization." };

const INVITE_EXPIRY_MS = 7 * 24 * 60 * 60 * 1000;

export async function inviteUserAction(tenantSlug: string, _prevState: InviteUserActionState, formData: FormData): Promise<InviteUserActionState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const email = String(formData.get("email") ?? "").trim();
  const displayName = String(formData.get("displayName") ?? "").trim();
  const orgUnitId = String(formData.get("orgUnitId") ?? "").trim() || null;

  const serviceRoleClient = createSupabaseServiceRoleClient();

  const { data: authResult, error: authError } = await serviceRoleClient.auth.admin.inviteUserByEmail(email);
  if (authError || !authResult.user) {
    return { error: `Could not send this invitation: ${authError?.message ?? "the identity provider returned no user"}` };
  }

  try {
    await inviteUser(toUserLifecycleRpcClient(serviceRoleClient), {
      tenantId: access.tenant.id,
      authUserId: authResult.user.id,
      email,
      displayName,
      orgUnitId,
      invitedBy: access.authUserId,
      inviteExpiresAt: new Date(Date.now() + INVITE_EXPIRY_MS).toISOString(),
    });
  } catch (error) {
    if (error instanceof UserLifecycleMutationError) return { error: `Could not record this invitation: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/users`);
  return OK;
}
