"use server";

/**
 * Expiry sweep trigger Server Action (CPL-322, CG-S13-CPL-024). Uses the
 * RLS-scoped `authenticated` client -- app.run_loyalty_expiry_sweep is
 * granted directly to `authenticated` and performs its own LYL:Edit
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses. Gated by resolveTenantAdminAccessForRequest (a coarse
 * tenant_admin portal-entry check) -- the real authority is enforced by the
 * RPC itself.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { runLoyaltyExpirySweep, LoyaltyExpiryFraudMutationError } from "../../../../../server/mutations/customer-portal-loyalty-expiry-fraud.ts";

export interface LoyaltyExpiryAdminFormState {
  readonly error: string | null;
}

const INITIAL_STATE: LoyaltyExpiryAdminFormState = { error: null };

function readNullableText(formData: FormData, key: string): string | null {
  const raw = String(formData.get(key) ?? "").trim();
  return raw.length === 0 ? null : raw;
}

export async function runLoyaltyExpirySweepAction(tenantSlug: string, _prevState: LoyaltyExpiryAdminFormState, formData: FormData): Promise<LoyaltyExpiryAdminFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's admin workspace." };

  const supabase = await createSupabaseServerClient();
  try {
    await runLoyaltyExpirySweep(supabase, {
      tenantId: access.tenant.id,
      runLabel: readNullableText(formData, "runLabel"),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof LoyaltyExpiryFraudMutationError) return { error: `Could not run the expiry sweep: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/loyalty-expiry`);
  return INITIAL_STATE;
}
