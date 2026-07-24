"use server";

/**
 * Prospect Lifecycle Server Actions (COM-144, CG-S7-COM-003). Uses the RLS-scoped
 * `authenticated` client -- app.disqualify_prospect/app.archive_prospect are granted
 * directly to `authenticated` and perform their own entitlement/record-scope checks
 * in-body, the same convention COM-143's own leads/actions.ts established.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { disqualifyProspect, archiveProspect, ProspectMutationError } from "../../../../../../server/mutations/prospect.ts";

export interface ProspectFormState {
  readonly error: string | null;
}

export async function disqualifyProspectAction(tenantSlug: string, prospectId: string, expectedVersion: number, reason: string): Promise<ProspectFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }
  if (!reason.trim()) {
    return { error: "A disqualification reason is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await disqualifyProspect(supabase, { prospectId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ProspectMutationError) {
      return { error: `Could not disqualify prospect: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/prospects/${prospectId}`);
  return { error: null };
}

export async function archiveProspectAction(tenantSlug: string, prospectId: string, expectedVersion: number): Promise<ProspectFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await archiveProspect(supabase, { prospectId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ProspectMutationError) {
      return { error: `Could not archive prospect: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/prospects/${prospectId}`);
  return { error: null };
}
