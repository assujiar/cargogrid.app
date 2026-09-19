"use server";

/**
 * Customer Portal Access Server Action (CG-AUDIT-2026-09-02 A2b), rendered
 * on the Account Detail page. Composes CPL-300's own already-tested
 * grantInitialCustomerPortalAccountAdmin mutation wrapper (server/mutations/
 * customer-portal-scope.ts), which that migration shipped with no UI caller
 * anywhere in this repository -- "the one deliberate exception to Layer-4-
 * only, never staff RBAC" (that RPC's own comment): a tenant admin seeds the
 * first account_admin on a brand-new account once, gated purely by the
 * RPC's own CPT:Create authority check (seeded since CPL-300, never used
 * from any UI until now) -- this file never re-derives that authority
 * client-side, it only forwards.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { grantInitialCustomerPortalAccountAdmin, CustomerPortalScopeMutationError } from "../../../../../../server/mutations/customer-portal-scope.ts";

export interface CustomerPortalAccessFormState {
  readonly error: string | null;
  readonly success: boolean;
}

const NO_ACCESS: CustomerPortalAccessFormState = { error: "You don't have access to this organization's Commercial workspace.", success: false };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function grantInitialCustomerPortalAccountAdminAction(
  tenantSlug: string,
  accountId: string,
  _prevState: CustomerPortalAccessFormState,
  formData: FormData,
): Promise<CustomerPortalAccessFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const authUserId = String(formData.get("authUserId") ?? "").trim();
  if (!authUserId || !UUID_RE.test(authUserId)) {
    return { error: "Enter the customer's CargoGrid account ID (a valid UUID) -- they must already have a CargoGrid identity before they can be granted access.", success: false };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await grantInitialCustomerPortalAccountAdmin(supabase, {
      tenantId: access.tenant.id,
      accountId,
      authUserId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CustomerPortalScopeMutationError) {
      return { error: `Could not grant customer portal access: ${error.message}`, success: false };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/accounts/${accountId}`);
  return { error: null, success: true };
}
