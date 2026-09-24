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
import { getEffectiveCustomerPrice, ContractQueryError } from "../../../../../../server/queries/contract.ts";
import { cloneQuotation, QuotationMutationError } from "../../../../../../server/mutations/quotation.ts";
import type { EffectiveCustomerPrice } from "../../../../../../server/contracts/contract/contract.ts";

export interface ContractFormState {
  readonly error: string | null;
}

export interface EffectiveCustomerPriceFormState {
  readonly error: string | null;
  readonly result: EffectiveCustomerPrice | null;
}

/**
 * CG-AUDIT-2026-09-02 E1 (bounded core): app.get_effective_customer_price
 * (COM-156) has been a fully-built, fully-tested, deterministic pricing
 * lookup since this capability shipped, but had zero callers anywhere in
 * app/ -- a tenant could build and publish a full contract price list end
 * to end and never see, anywhere, what price the system would actually
 * resolve for a real lane/service. This is the first real caller. Read-
 * only (no mutation, no revalidatePath); `no_effective_price` is a real,
 * expected outcome (no matching component), surfaced as a friendly result
 * state rather than a thrown error.
 */
export async function checkEffectiveCustomerPriceAction(
  tenantSlug: string,
  accountId: string,
  serviceType: string,
  mode: string | null,
  originLane: string | null,
  destinationLane: string | null,
  equipmentType: string | null,
): Promise<EffectiveCustomerPriceFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace.", result: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const result = await getEffectiveCustomerPrice(supabase, {
      tenantId: access.tenant.id,
      accountId,
      serviceType,
      mode,
      originLane,
      destinationLane,
      equipmentType,
      actorAuthUserId: access.authUserId,
    });
    return { error: null, result };
  } catch (error) {
    if (error instanceof ContractQueryError) {
      if (error.message.startsWith("no_effective_price")) {
        return { error: "No published price component matches these criteria.", result: null };
      }
      return { error: `Could not resolve a price: ${error.message}`, result: null };
    }
    throw error;
  }
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

/**
 * CG-AUDIT-2026-09-02 E1 (repeat-order bounded core): reuses the existing "clone a
 * prior draft" flow (app.clone_quotation, COM-152 -- already wired as
 * cloneQuotationAction on the quotation detail page) as the practical "repeat this
 * contract as a new order" entry point, right from the contract that actually
 * governs the pricing. Creates a brand-new draft quotation with the same customer/
 * lines/terms as the contract's own originating quotation; every job order booked
 * from it still goes through the full accept/convert/handoff chain unchanged --
 * this never lets a job order skip quotation. Inventing a no-quotation booking path
 * remains the separate, genuine product decision the backlog's own E1 disposition
 * already identifies.
 */
export async function repeatContractAsQuotationAction(tenantSlug: string, sourceQuotationId: string): Promise<ContractFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  let cloneId: string;
  try {
    const clone = await cloneQuotation(supabase, { sourceQuotationId, actorAuthUserId: access.authUserId, createdBy: access.authUserId });
    cloneId = clone.id;
  } catch (error) {
    if (error instanceof QuotationMutationError) {
      return { error: `Could not create a repeat quotation: ${error.message}` };
    }
    throw error;
  }

  redirect(`/${tenantSlug}/commercial/quotations/${cloneId}`);
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
