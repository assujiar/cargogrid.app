"use server";

/**
 * Customer Contract detail Server Actions (COM-156, CG-S7-COM-015). Every app.* RPC
 * below is granted directly to `authenticated` and performs its own COM:Edit/COM:Approve/
 * authority check in-body, the same convention every prior Commercial capability's
 * actions.ts already uses.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import {
  createCustomerContractDraft,
  addCustomerContractPriceComponent,
  removeCustomerContractPriceComponent,
  publishCustomerContract,
  retireCustomerContract,
  ContractMutationError,
} from "../../../../../../server/mutations/contract.ts";

export interface ContractFormState {
  readonly error: string | null;
}

export async function addPriceComponentAction(
  tenantSlug: string,
  contractId: string,
  serviceType: string,
  mode: string | null,
  originLane: string | null,
  destinationLane: string | null,
  equipmentType: string | null,
  currency: string,
  baseAmount: number,
  minimumAmount: number | null,
  discountPct: number,
): Promise<ContractFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await addCustomerContractPriceComponent(supabase, {
      contractId,
      serviceType,
      mode,
      originLane,
      destinationLane,
      equipmentType,
      currency,
      baseAmount,
      minimumAmount,
      discountPct,
      surchargeComponents: [],
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ContractMutationError) {
      return { error: `Could not add price component: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/contracts/${contractId}`);
  return { error: null };
}

/** Bound directly to a <form action={...}> -- every argument this action needs is already bound. */
export async function removePriceComponentAction(tenantSlug: string, contractId: string, componentId: string, _formData: FormData): Promise<void> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return;
  }

  const supabase = await createSupabaseServerClient();
  try {
    await removeCustomerContractPriceComponent(supabase, { componentId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ContractMutationError) {
      return;
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/contracts/${contractId}`);
}

/** Bound directly to a <form action={...}>. Publish/retire are the governance-weighted, COM:Approve-gated transitions -- failures are swallowed here (the page's own re-render surfaces current status), matching every other bound-form-action mutation's posture in this repository. */
export async function publishContractAction(tenantSlug: string, contractId: string, expectedVersion: number, _formData: FormData): Promise<void> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return;
  }

  const supabase = await createSupabaseServerClient();
  try {
    await publishCustomerContract(supabase, { contractId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ContractMutationError) {
      return;
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/contracts/${contractId}`);
}

export async function retireContractAction(tenantSlug: string, contractId: string, expectedVersion: number, reason: string): Promise<ContractFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await retireCustomerContract(supabase, { contractId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ContractMutationError) {
      return { error: `Could not retire contract: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/contracts/${contractId}`);
  return { error: null };
}

/** Alternative flow (Prompt 156 §22): renewal/amendment from a current or historical version -- redirects to the new draft's own detail page, the same "redirect to the new version" pattern createQuotationRevisionAction (COM-152) established. */
export async function createContractRenewalAction(tenantSlug: string, sourceContractId: string, effectiveFrom: string, effectiveTo: string | null, reason: string): Promise<ContractFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  let newId: string;
  try {
    const draft = await createCustomerContractDraft(supabase, {
      sourceContractId,
      effectiveFrom,
      effectiveTo,
      amendmentReason: reason,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    newId = draft.id;
  } catch (error) {
    if (error instanceof ContractMutationError) {
      return { error: `Could not create renewal: ${error.message}` };
    }
    throw error;
  }

  redirect(`/${tenantSlug}/commercial/contracts/${newId}`);
}
