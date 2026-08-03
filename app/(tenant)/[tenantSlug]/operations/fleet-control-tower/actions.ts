"use server";

/**
 * Fleet Control Tower review Server Actions (ATW-226H). Thin wrappers over ATW-226G's
 * own confirm/dismiss RPCs -- confirmMilestoneCandidateAction/confirmExceptionSignalAction
 * are the only paths this UI has to create a real app.milestone_events/app.operational_
 * exceptions row, and both always use the signed-in reviewer's own real, RBAC-checked
 * identity (never a system bypass -- see the ATW-226G migration's own design note 1).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveOperationsAccessForRequest } from "../../../../../lib/portal/resolve-operations-access.server.ts";
import {
  confirmMilestoneCandidate,
  dismissMilestoneCandidate,
  confirmExceptionSignal,
  dismissExceptionSignal,
  GeofenceSignalsMutationError,
} from "../../../../../server/mutations/geofence-route-deviation-signals.ts";

export interface FleetControlTowerFormState {
  readonly error: string | null;
}

export async function confirmMilestoneCandidateAction(
  tenantSlug: string,
  candidateId: string,
  _prevState: FleetControlTowerFormState,
  formData: FormData,
): Promise<FleetControlTowerFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const overrideConflict = formData.get("overrideConflict") === "on";
  const supabase = await createSupabaseServerClient();
  try {
    await confirmMilestoneCandidate(supabase, {
      candidateId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
      overrideConflict,
    });
  } catch (error) {
    if (error instanceof GeofenceSignalsMutationError) {
      return { error: `Could not confirm this milestone candidate: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet-control-tower`);
  return { error: null };
}

export async function dismissMilestoneCandidateAction(
  tenantSlug: string,
  candidateId: string,
  _prevState: FleetControlTowerFormState,
  formData: FormData,
): Promise<FleetControlTowerFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reviewNote = String(formData.get("reviewNote") ?? "").trim();
  const supabase = await createSupabaseServerClient();
  try {
    await dismissMilestoneCandidate(supabase, { candidateId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, reviewNote });
  } catch (error) {
    if (error instanceof GeofenceSignalsMutationError) {
      return { error: `Could not dismiss this milestone candidate: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet-control-tower`);
  return { error: null };
}

export async function confirmExceptionSignalAction(
  tenantSlug: string,
  signalId: string,
  _prevState: FleetControlTowerFormState,
  _formData: FormData,
): Promise<FleetControlTowerFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await confirmExceptionSignal(supabase, { signalId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof GeofenceSignalsMutationError) {
      return { error: `Could not confirm this exception signal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet-control-tower`);
  return { error: null };
}

export async function dismissExceptionSignalAction(
  tenantSlug: string,
  signalId: string,
  _prevState: FleetControlTowerFormState,
  formData: FormData,
): Promise<FleetControlTowerFormState> {
  const access = await resolveOperationsAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Operations workspace." };
  }

  const reviewNote = String(formData.get("reviewNote") ?? "").trim();
  const supabase = await createSupabaseServerClient();
  try {
    await dismissExceptionSignal(supabase, { signalId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId, reviewNote });
  } catch (error) {
    if (error instanceof GeofenceSignalsMutationError) {
      return { error: `Could not dismiss this exception signal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/operations/fleet-control-tower`);
  return { error: null };
}
