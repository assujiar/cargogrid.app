"use server";

/**
 * Rate Version Server Actions (COM-149, CG-S7-COM-008). Uses the RLS-scoped
 * `authenticated` client -- app.approve_rate_version/app.reject_rate_version/
 * app.withdraw_rate_version are all granted directly to `authenticated` and perform their
 * own app.is_support_grant_authority entitlement check in-body, the same convention every
 * prior Commercial capability's actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { approveRateVersion, rejectRateVersion, withdrawRateVersion, RateMutationError } from "../../../../../../server/mutations/rate.ts";

export interface RateActionFormState {
  readonly error: string | null;
}

export async function approveRateVersionAction(tenantSlug: string, rateVersionId: string, expectedVersion: number): Promise<RateActionFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveRateVersion(supabase, { rateVersionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RateMutationError) {
      return { error: `Could not approve rate version: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/rates/${rateVersionId}`);
  revalidatePath(`/${tenantSlug}/commercial/rates`);
  return { error: null };
}

export async function rejectRateVersionAction(tenantSlug: string, rateVersionId: string, expectedVersion: number, reason: string): Promise<RateActionFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await rejectRateVersion(supabase, { rateVersionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RateMutationError) {
      return { error: `Could not reject rate version: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/rates/${rateVersionId}`);
  revalidatePath(`/${tenantSlug}/commercial/rates`);
  return { error: null };
}

export async function withdrawRateVersionAction(tenantSlug: string, rateVersionId: string, expectedVersion: number, reason: string): Promise<RateActionFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await withdrawRateVersion(supabase, { rateVersionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof RateMutationError) {
      return { error: `Could not withdraw rate version: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/rates/${rateVersionId}`);
  revalidatePath(`/${tenantSlug}/commercial/rates`);
  return { error: null };
}
