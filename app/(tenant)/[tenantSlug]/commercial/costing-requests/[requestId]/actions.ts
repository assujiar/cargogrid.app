"use server";

/**
 * Costing Request Server Actions (COM-148, CG-S7-COM-007). Uses the RLS-scoped
 * `authenticated` client -- app.assign_costing_request/app.submit_costing_response/
 * app.revise_costing_request/app.cancel_costing_request are all granted directly to
 * `authenticated` and perform their own entitlement/record-scope checks in-body, the same
 * convention every prior Commercial capability's actions.ts already uses.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import { assignCostingRequest, submitCostingResponse, reviseCostingRequest, cancelCostingRequest, CostingMutationError } from "../../../../../../server/mutations/costing.ts";
import { selectVendorRate, RateMutationError } from "../../../../../../server/mutations/rate.ts";
import type { CostingResponseSourceType, ResponseComponentInput } from "../../../../../../server/contracts/costing/costing.ts";

export interface CostingRequestFormState {
  readonly error: string | null;
}

/** Requires both COM:Edit and COM:View cost (the same dual gate app.submit_costing_response uses). Snapshots the selected rate (or an ad-hoc entry) into app.rate_selections. */
export async function selectVendorRateAction(
  tenantSlug: string,
  requestId: string,
  rateVersionId: string | null,
  isAdhoc: boolean,
  adhocCurrency: string | null,
  adhocAmount: number | null,
  overrideReason: string | null,
): Promise<CostingRequestFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await selectVendorRate(supabase, {
      costingRequestId: requestId,
      rateVersionId,
      isAdhoc,
      adhocCurrency,
      adhocAmount,
      overrideReason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof RateMutationError) {
      return { error: `Could not select a rate: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/costing-requests/${requestId}`);
  return { error: null };
}

export async function assignCostingRequestAction(tenantSlug: string, requestId: string, expectedVersion: number, assigneeUserId: string): Promise<CostingRequestFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await assignCostingRequest(supabase, { requestId, expectedVersion, assigneeUserId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CostingMutationError) {
      return { error: `Could not assign costing request: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/costing-requests/${requestId}`);
  return { error: null };
}

export async function submitCostingResponseAction(
  tenantSlug: string,
  requestId: string,
  sourceType: CostingResponseSourceType,
  vendorRef: string | null,
  currency: string,
  expiryAt: string | null,
  components: ResponseComponentInput[],
): Promise<CostingRequestFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitCostingResponse(supabase, {
      requestId,
      sourceType,
      vendorRef,
      currency,
      expiryAt,
      components,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CostingMutationError) {
      return { error: `Could not submit costing response: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/costing-requests/${requestId}`);
  return { error: null };
}

/** Redirects to the new revision on success -- the source request remains reachable (status=superseded) but is no longer the active one. */
export async function reviseCostingRequestAction(tenantSlug: string, requestId: string): Promise<CostingRequestFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  let newRequestId: string;
  try {
    const revised = await reviseCostingRequest(supabase, { requestId, actorAuthUserId: access.authUserId, createdBy: access.authUserId });
    newRequestId = revised.id;
  } catch (error) {
    if (error instanceof CostingMutationError) {
      return { error: `Could not revise costing request: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/costing-requests/${requestId}`);
  redirect(`/${tenantSlug}/commercial/costing-requests/${newRequestId}`);
}

export async function cancelCostingRequestAction(tenantSlug: string, requestId: string, expectedVersion: number, reason: string): Promise<CostingRequestFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelCostingRequest(supabase, { requestId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CostingMutationError) {
      return { error: `Could not cancel costing request: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/costing-requests/${requestId}`);
  return { error: null };
}
