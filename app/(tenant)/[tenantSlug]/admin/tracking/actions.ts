"use server";

/**
 * Tenant tracking source policy Server Action (ATW-226H, extends ATW-226A's own
 * backend). Package/entitlement assignment is deliberately not editable from this
 * form -- see page.tsx's own header comment.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveTenantAdminAccessForRequest } from "../../../../../lib/portal/resolve-tenant-admin-access.server.ts";
import { upsertTenantTrackingSourcePolicy, TrackingSourcePolicyMutationError } from "../../../../../server/mutations/tracking-source-policy.ts";
import type { TrackingSourceType } from "../../../../../server/contracts/tracking-source-policy/tracking-source-policy.ts";

export interface TrackingPolicyFormState {
  readonly error: string | null;
}

export async function upsertTrackingSourcePolicyAction(
  tenantSlug: string,
  _prevState: TrackingPolicyFormState,
  formData: FormData,
): Promise<TrackingPolicyFormState> {
  const access = await resolveTenantAdminAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's admin area." };
  }

  const defaultSourcePriority = formData.getAll("defaultSourcePriority").map((v) => String(v)) as TrackingSourceType[];
  const freshnessThresholdSeconds = Number(formData.get("freshnessThresholdSeconds") ?? 0);
  const accuracyThresholdMeters = Number(formData.get("accuracyThresholdMeters") ?? 0);
  const switchHysteresisSeconds = Number(formData.get("switchHysteresisSeconds") ?? 0);

  const supabase = await createSupabaseServerClient();
  try {
    await upsertTenantTrackingSourcePolicy(supabase, {
      tenantId: access.tenant.id,
      defaultSourcePriority,
      freshnessThresholdSeconds,
      accuracyThresholdMeters,
      switchHysteresisSeconds,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TrackingSourcePolicyMutationError) {
      return { error: `Could not save the tracking source policy: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/admin/tracking`);
  return { error: null };
}
