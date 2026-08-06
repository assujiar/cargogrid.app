"use server";

/**
 * Vendor intake configuration Server Action (PRC-251, CG-S11-PRC-002). Toggles the
 * tenant-scoped procurement.vendor_self_registration.enabled flag via the existing
 * Configuration Engine service layer (PLT-121) -- no new schema, the exact ATW-226A
 * precedent. Gated by the Configuration Engine's own authority
 * (app.check_config_object_authority, tenant_admin/Supreme for a tenant-scoped
 * object), matching Prompt 251 §26's "tenant admins configure intake."
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import { createConfigDraft, setConfigItems, publishConfigVersion, ConfigMutationError, type ConfigMutationRpcClient } from "../../../../../../server/mutations/config.ts";

const SELF_REGISTRATION_KEY = "procurement.vendor_self_registration.enabled";

export interface IntakeConfigActionState {
  readonly error: string | null;
}

export async function setVendorSelfRegistrationEnabledAction(tenantSlug: string, _prevState: IntakeConfigActionState, formData: FormData): Promise<IntakeConfigActionState> {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return { error: "You don't have access to this organization's Procurement workspace." };

  const enabled = formData.get("enabled") === "on";

  const supabaseClient = await createSupabaseServerClient();
  // supabase.rpc() returns a thenable PostgrestFilterBuilder, not a structural
  // Promise (missing catch/finally) -- this async wrapper normalizes it to the plain
  // Promise shape ConfigMutationRpcClient declares, the same adapter pattern
  // app/(tenant)/[tenantSlug]/operations/fleet/page.tsx already established.
  const supabase: ConfigMutationRpcClient = { rpc: async (fn, args) => await supabaseClient.rpc(fn, args) };
  try {
    const draft = await createConfigDraft(supabase, {
      configTypeCode: "feature",
      tenantId: access.tenant.id,
      scopeLevel: "tenant",
      scopeId: null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    await setConfigItems(supabase, {
      versionId: draft.id,
      items: [{ key: SELF_REGISTRATION_KEY, value: enabled, canonicalRef: null }],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    await publishConfigVersion(supabase, { versionId: draft.id, actorAuthUserId: access.authUserId, effectiveFrom: null, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ConfigMutationError) return { error: `Could not update self-registration: ${error.message}` };
    throw error;
  }

  revalidatePath(`/${tenantSlug}/procurement/vendors/intake`);
  return { error: null };
}
