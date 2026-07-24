"use server";

/**
 * Opportunity Management Server Actions (COM-147, CG-S7-COM-006). Uses the RLS-scoped
 * `authenticated` client -- app.create_opportunity/app.update_opportunity/
 * app.transition_opportunity_stage/app.clone_opportunity are all granted directly to
 * `authenticated` and perform their own entitlement/record-scope checks in-body, the same
 * convention every prior Commercial capability's actions.ts already uses.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../lib/portal/resolve-commercial-access.server.ts";
import { createOpportunity, updateOpportunity, transitionOpportunityStage, cloneOpportunity, OpportunityMutationError } from "../../../../../server/mutations/opportunity.ts";
import { requestCosting, CostingMutationError } from "../../../../../server/mutations/costing.ts";
import type { OpportunityStage } from "../../../../../server/contracts/opportunity/opportunity.ts";
import type { RequestComponentInput } from "../../../../../server/contracts/costing/costing.ts";

export interface OpportunityFormState {
  readonly error: string | null;
}

export async function createOpportunityAction(tenantSlug: string, _prevState: OpportunityFormState, formData: FormData): Promise<OpportunityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to create an opportunity in this organization." };
  }

  const prospectId = String(formData.get("prospectId") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();

  if (!prospectId) {
    return { error: "A prospect ID is required." };
  }
  if (!name) {
    return { error: "An opportunity name is required." };
  }

  const supabase = await createSupabaseServerClient();
  let opportunityId: string;
  try {
    const opportunity = await createOpportunity(supabase, {
      tenantId: access.tenant.id,
      prospectId,
      name,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    opportunityId = opportunity.id;
  } catch (error) {
    if (error instanceof OpportunityMutationError) {
      return { error: `Could not create opportunity: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/opportunities`);
  redirect(`/${tenantSlug}/commercial/opportunities/${opportunityId}`);
}

export async function updateOpportunityRequirementsAction(
  tenantSlug: string,
  opportunityId: string,
  expectedVersion: number,
  requirements: { serviceType: string; cargoDescription: string; origin: string; destination: string; targetReadyDate: string },
  nextAction: string,
): Promise<OpportunityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateOpportunity(supabase, {
      opportunityId,
      expectedVersion,
      requirements: {
        serviceType: requirements.serviceType || null,
        cargoDescription: requirements.cargoDescription || null,
        origin: requirements.origin || null,
        destination: requirements.destination || null,
        targetReadyDate: requirements.targetReadyDate || null,
      },
      nextAction: nextAction || null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OpportunityMutationError) {
      return { error: `Could not update opportunity: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/opportunities/${opportunityId}`);
  return { error: null };
}

export async function updateOpportunityValueAction(
  tenantSlug: string,
  opportunityId: string,
  expectedVersion: number,
  valueAmount: number,
  valueCurrency: string,
): Promise<OpportunityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateOpportunity(supabase, {
      opportunityId,
      expectedVersion,
      valueAmount,
      valueCurrency,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OpportunityMutationError) {
      return { error: `Could not set opportunity value: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/opportunities/${opportunityId}`);
  return { error: null };
}

export async function transitionOpportunityStageAction(
  tenantSlug: string,
  opportunityId: string,
  expectedVersion: number,
  newStage: OpportunityStage,
  closeReason: string | null,
): Promise<OpportunityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await transitionOpportunityStage(supabase, {
      opportunityId,
      expectedVersion,
      newStage,
      closeReason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof OpportunityMutationError) {
      return { error: `Could not change opportunity stage: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/opportunities/${opportunityId}`);
  revalidatePath(`/${tenantSlug}/commercial/opportunities`);
  return { error: null };
}

export async function cloneOpportunityAction(tenantSlug: string, opportunityId: string, name: string): Promise<OpportunityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  let cloneId: string;
  try {
    const clone = await cloneOpportunity(supabase, {
      opportunityId,
      name: name || null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    cloneId = clone.id;
  } catch (error) {
    if (error instanceof OpportunityMutationError) {
      return { error: `Could not clone opportunity: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/opportunities`);
  redirect(`/${tenantSlug}/commercial/opportunities/${cloneId}`);
}

/** Blocked server-side unless app.get_opportunity_costing_readiness reports ready=true first (COM-148). Idempotent on (opportunity, current version) -- a retry never creates a duplicate request. */
export async function requestCostingAction(
  tenantSlug: string,
  opportunityId: string,
  components: RequestComponentInput[],
  dueAt: string | null,
): Promise<OpportunityFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  let requestId: string;
  try {
    const request = await requestCosting(supabase, {
      opportunityId,
      components,
      dueAt,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
    requestId = request.id;
  } catch (error) {
    if (error instanceof CostingMutationError) {
      return { error: `Could not request costing: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/opportunities/${opportunityId}`);
  redirect(`/${tenantSlug}/commercial/costing-requests/${requestId}`);
}
