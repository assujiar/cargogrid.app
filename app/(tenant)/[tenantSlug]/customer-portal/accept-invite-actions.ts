"use server";

/**
 * Accept-a-pending-customer-portal-invite Server Action (CG-AUDIT-2026-09-02
 * A2b). Composes CPL-300's own already-tested acceptCustomerPortalInvite
 * mutation wrapper (server/mutations/customer-portal-scope.ts), which that
 * migration shipped with no UI caller anywhere in this repository.
 *
 * Deliberately does NOT go through resolveCustomerPortalAccessForRequest --
 * that guard denies exactly the identity this action exists to serve (an
 * invited-but-not-yet-accepted identity holds no active customer_user-layer
 * principal yet; the layer is granted by app.accept_customer_portal_invite
 * itself, on genuine acceptance, mirroring page.tsx's own forbidden-branch
 * pending-invite check). Authentication is verified directly via
 * supabase.auth.getUser() instead; the RPC's own server-side auth_user_id
 * equality check (accept_customer_portal_invite raises customer_portal_
 * membership_not_found for any membershipId not owned by the caller) is the
 * real authority boundary, never re-derived here.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { acceptCustomerPortalInvite, CustomerPortalScopeMutationError } from "../../../../server/mutations/customer-portal-scope.ts";

export interface AcceptCustomerPortalInviteActionState {
  readonly error: string | null;
}

const OK: AcceptCustomerPortalInviteActionState = { error: null };
const NOT_SIGNED_IN: AcceptCustomerPortalInviteActionState = { error: "Your session has expired. Please sign in again." };

export async function acceptCustomerPortalInviteAction(
  tenantSlug: string,
  _prevState: AcceptCustomerPortalInviteActionState,
  formData: FormData,
): Promise<AcceptCustomerPortalInviteActionState> {
  const supabase = await createSupabaseServerClient();
  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData.user) return NOT_SIGNED_IN;

  const membershipId = String(formData.get("membershipId") ?? "").trim();
  const expectedVersionRaw = String(formData.get("expectedVersion") ?? "").trim();
  const expectedVersion = Number(expectedVersionRaw);
  if (!membershipId || !Number.isInteger(expectedVersion)) {
    return { error: "This invite could not be identified." };
  }

  try {
    await acceptCustomerPortalInvite(supabase, {
      membershipId,
      expectedVersion,
      authUserId: userData.user.id,
    });
  } catch (error) {
    if (error instanceof CustomerPortalScopeMutationError) {
      return { error: `Could not accept this invite: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/customer-portal`);
  return OK;
}
