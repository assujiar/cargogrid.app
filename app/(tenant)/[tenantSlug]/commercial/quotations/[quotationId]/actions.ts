"use server";

/**
 * Quotation Builder Server Actions (COM-151, CG-S7-COM-010). Uses the RLS-scoped
 * `authenticated` client -- every app.* RPC below is granted directly to `authenticated`
 * and performs its own COM:Edit/COM:Create/record-access check in-body, the same
 * convention every prior Commercial capability's actions.ts already uses.
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import {
  addQuotationLine,
  removeQuotationLine,
  updateQuotationTerms,
  submitQuotation,
  cloneQuotation,
  QuotationMutationError,
} from "../../../../../../server/mutations/quotation.ts";
import type { QuotationLineType, QuotationTerms } from "../../../../../../server/contracts/quotation/quotation.ts";

export interface QuotationFormState {
  readonly error: string | null;
}

export async function addQuotationLineAction(
  tenantSlug: string,
  quotationId: string,
  expectedVersion: number,
  lineType: QuotationLineType,
  description: string,
  marginCalculationId: string | null,
  quantity: number,
  unitPrice: number,
  discountPct: number,
  taxPct: number,
): Promise<QuotationFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await addQuotationLine(supabase, {
      quotationId,
      expectedVersion,
      lineType,
      description,
      marginCalculationId,
      quantity,
      unitPrice,
      discountPct,
      taxPct,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof QuotationMutationError) {
      return { error: `Could not add line: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/quotations/${quotationId}`);
  return { error: null };
}

/** Bound directly to a <form action={...}> -- every argument this action needs is already bound. */
export async function removeQuotationLineAction(
  tenantSlug: string,
  quotationId: string,
  expectedVersion: number,
  lineId: string,
  _formData: FormData,
): Promise<void> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return;
  }

  const supabase = await createSupabaseServerClient();
  try {
    await removeQuotationLine(supabase, { quotationId, expectedVersion, lineId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof QuotationMutationError) {
      return;
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/quotations/${quotationId}`);
}

export async function updateQuotationTermsAction(
  tenantSlug: string,
  quotationId: string,
  expectedVersion: number,
  currency: string,
  validityFrom: string,
  validityTo: string,
  terms: QuotationTerms,
  contactId: string | null,
): Promise<QuotationFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await updateQuotationTerms(supabase, {
      quotationId,
      expectedVersion,
      currency,
      validityFrom,
      validityTo,
      terms,
      contactId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof QuotationMutationError) {
      return { error: `Could not update terms: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/quotations/${quotationId}`);
  return { error: null };
}

/** Fails closed with the exact blocking reasons (submission_not_ready) -- surfaced to the caller rather than swallowed, unlike the bound-form-action mutations above, since a failed submit is the one action a user needs specific feedback on. */
export async function submitQuotationAction(tenantSlug: string, quotationId: string, expectedVersion: number): Promise<QuotationFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitQuotation(supabase, { quotationId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof QuotationMutationError) {
      return { error: `Could not submit quotation: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/quotations/${quotationId}`);
  return { error: null };
}

/** The "clone a prior draft with explicit origin" alternative flow (Prompt 151 §22) -- redirects to the new draft's own builder page. */
export async function cloneQuotationAction(tenantSlug: string, sourceQuotationId: string): Promise<QuotationFormState> {
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
      return { error: `Could not clone quotation: ${error.message}` };
    }
    throw error;
  }

  redirect(`/${tenantSlug}/commercial/quotations/${cloneId}`);
}
