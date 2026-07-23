"use server";

/**
 * Shared Activity Server Actions (COM-145, CG-S7-COM-004) -- used by both the Lead
 * Detail (COM-143) and Prospect Detail (COM-144) pages, since app.activities links
 * polymorphically to either. A private (`_shared`) folder, not a route segment.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { logActivity, completeActivity, rescheduleActivity, cancelActivity, ContactMutationError } from "../../../../../server/mutations/contact.ts";
import type { ActivityType, RelatedType } from "../../../../../server/contracts/contact/contact.ts";

export interface ActivityFormState {
  readonly error: string | null;
}

/** Maps a polymorphic related_type to its own route segment (COM-147 added 'opportunity' -- a bare lead/prospect ternary would silently under-revalidate the Opportunity Detail page). */
function relatedTypeRouteSegment(relatedType: RelatedType): string {
  switch (relatedType) {
    case "lead":
      return "leads";
    case "prospect":
      return "prospects";
    case "opportunity":
      return "opportunities";
  }
}

export async function logActivityAction(
  tenantSlug: string,
  relatedType: RelatedType,
  relatedId: string,
  type: ActivityType,
  subject: string,
  status: "scheduled" | "completed",
  dueAt: string | null,
): Promise<ActivityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }
  if (!subject.trim()) {
    return { error: "A subject is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await logActivity(supabase, {
      relatedType,
      relatedId,
      type,
      subject,
      status,
      dueAt: status === "scheduled" ? dueAt : null,
      completedAt: status === "completed" ? new Date().toISOString() : null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ContactMutationError) {
      return { error: `Could not log activity: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/${relatedTypeRouteSegment(relatedType)}/${relatedId}`);
  return { error: null };
}

export async function completeActivityAction(tenantSlug: string, relatedType: RelatedType, relatedId: string, activityId: string, expectedVersion: number, outcome: string): Promise<ActivityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await completeActivity(supabase, { activityId, expectedVersion, outcome: outcome || null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ContactMutationError) {
      return { error: `Could not complete activity: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/${relatedTypeRouteSegment(relatedType)}/${relatedId}`);
  return { error: null };
}

export async function cancelActivityAction(tenantSlug: string, relatedType: RelatedType, relatedId: string, activityId: string, expectedVersion: number): Promise<ActivityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelActivity(supabase, { activityId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ContactMutationError) {
      return { error: `Could not cancel activity: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/${relatedTypeRouteSegment(relatedType)}/${relatedId}`);
  return { error: null };
}

export async function rescheduleActivityAction(
  tenantSlug: string,
  relatedType: RelatedType,
  relatedId: string,
  activityId: string,
  expectedVersion: number,
  newDueAt: string,
): Promise<ActivityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await rescheduleActivity(supabase, { activityId, expectedVersion, newDueAt, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ContactMutationError) {
      return { error: `Could not reschedule activity: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/${relatedTypeRouteSegment(relatedType)}/${relatedId}`);
  return { error: null };
}
