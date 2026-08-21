"use server";

/**
 * Analytics and Materialized Views server actions (IAE-005, Prompt 333).
 * app.refresh_analytics_view is Supreme-only and system-wide (one shared
 * materialized view spans every tenant) -- this action is reachable from any
 * tenant's own /analytics page, but the RPC itself is the real enforcement
 * point, mirroring every prior report action's convention.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../lib/portal/resolve-commercial-access.server.ts";
import { refreshAnalyticsView, AnalyticsMutationError } from "../../../../server/mutations/analytics.ts";

export interface AnalyticsActionState {
  readonly error: string | null;
}

const OK: AnalyticsActionState = { error: null };

export async function refreshAnalyticsViewAction(tenantSlug: string, viewCode: string, _prevState: AnalyticsActionState, _formData: FormData): Promise<AnalyticsActionState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await refreshAnalyticsView(supabase, { viewCode, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AnalyticsMutationError && error.code === "insufficient_authority") {
      return { error: "Only Supreme Admin may refresh an analytics view." };
    }
    if (error instanceof AnalyticsMutationError) {
      return { error: error.message };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/analytics`);
  return OK;
}
