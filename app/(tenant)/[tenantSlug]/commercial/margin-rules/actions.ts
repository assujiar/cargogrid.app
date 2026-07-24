"use server";

/**
 * Margin Rule Server Actions (COM-150, CG-S7-COM-009). Uses the RLS-scoped
 * `authenticated` client -- app.create_margin_rule_version/app.publish_margin_rule_version
 * are granted directly to `authenticated` and perform their own COM:Create/COM:Approve
 * entitlement check in-body, the same convention every prior Commercial capability's
 * actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createMarginRuleVersion, publishMarginRuleVersion, MarginMutationError } from "../../../../../server/mutations/margin.ts";

export interface MarginRuleFormState {
  readonly error: string | null;
}

export async function createMarginRuleVersionAction(tenantSlug: string, _prevState: MarginRuleFormState, formData: FormData): Promise<MarginRuleFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const minimumMarginPct = Number(formData.get("minimumMarginPct") ?? "");
  const roundingMode = String(formData.get("roundingMode") ?? "half_up");

  if (!Number.isFinite(minimumMarginPct) || minimumMarginPct < 0 || minimumMarginPct > 100) {
    return { error: "A minimum margin percentage between 0 and 100 is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createMarginRuleVersion(supabase, {
      tenantId: access.tenant.id,
      minimumMarginPct,
      roundingMode: roundingMode as "half_up" | "half_even" | "floor" | "ceiling",
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof MarginMutationError) {
      return { error: `Could not create margin rule: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/margin-rules`);
  return { error: null };
}

/** Bound directly to a <form action={...}> -- FormData is appended automatically by the form submission but unused here (every argument this action needs is already bound). */
export async function publishMarginRuleVersionAction(
  tenantSlug: string,
  ruleVersionId: string,
  expectedVersion: number,
  supersedesVersionId: string | null,
  _formData: FormData,
): Promise<void> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return;
  }

  const supabase = await createSupabaseServerClient();
  try {
    await publishMarginRuleVersion(supabase, { ruleVersionId, expectedVersion, supersedesVersionId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof MarginMutationError) {
      return;
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/margin-rules`);
}
