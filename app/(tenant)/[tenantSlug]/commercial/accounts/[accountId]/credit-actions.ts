"use server";

/**
 * Credit and Commercial Control Server Actions (COM-157, CG-S7-COM-016). Uses the
 * RLS-scoped `authenticated` client -- every app.* RPC below is granted directly to
 * `authenticated` and performs its own COM:Create/COM:Approve/reauth-freshness check
 * in-body, the same convention every prior Commercial capability's actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveCommercialAccessForRequest } from "../../../../../../lib/portal/resolve-commercial-access.server.ts";
import {
  requestCustomerCreditProfile,
  decideCreditProfileApprovalStep,
  holdCreditProfile,
  releaseCreditProfile,
  createCreditOverride,
  checkCustomerCredit,
  CreditMutationError,
} from "../../../../../../server/mutations/credit.ts";
import type { CreditCheckResult } from "../../../../../../server/contracts/credit/credit.ts";

export interface CreditFormState {
  readonly error: string | null;
}

export async function requestCreditProfileAction(tenantSlug: string, accountId: string, currency: string, requestedLimitAmount: number, _prevState: CreditFormState, _formData: FormData): Promise<CreditFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await requestCustomerCreditProfile(supabase, { tenantId: access.tenant.id, accountId, currency, requestedLimitAmount, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CreditMutationError) {
      return { error: `Could not request a credit profile: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/accounts/${accountId}`);
  return { error: null };
}

/** reauthConfirmed is the caller's own attestation, captured client-side as "now" at submit time -- see the migration/contract header for the disclosed no-live-MFA-challenge-UI boundary this reuses PLT-115's own reauth-freshness mechanism for. */
export async function decideCreditProfileApprovalStepAction(tenantSlug: string, accountId: string, requestStepId: string, decision: "approved" | "rejected", reason: string | null, reauthConfirmedAt: string): Promise<CreditFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await decideCreditProfileApprovalStep(supabase, { requestStepId, decision, reason, reauthConfirmedAt, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CreditMutationError) {
      return { error: `Could not record decision: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/accounts/${accountId}`);
  revalidatePath(`/${tenantSlug}/commercial/credit-approvals`);
  return { error: null };
}

export async function holdCreditProfileAction(tenantSlug: string, accountId: string, profileId: string, expectedVersion: number, reason: string, reauthConfirmedAt: string): Promise<CreditFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await holdCreditProfile(supabase, { profileId, expectedVersion, reason, reauthConfirmedAt, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CreditMutationError) {
      return { error: `Could not hold the credit profile: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/accounts/${accountId}`);
  return { error: null };
}

export async function releaseCreditProfileAction(tenantSlug: string, accountId: string, profileId: string, expectedVersion: number, reauthConfirmedAt: string): Promise<CreditFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await releaseCreditProfile(supabase, { profileId, expectedVersion, reauthConfirmedAt, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CreditMutationError) {
      return { error: `Could not release the credit profile: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/accounts/${accountId}`);
  return { error: null };
}

export async function createCreditOverrideAction(tenantSlug: string, accountId: string, profileId: string, amount: number, reason: string, expiresAt: string, reauthConfirmedAt: string): Promise<CreditFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createCreditOverride(supabase, { profileId, amount, reason, expiresAt, reauthConfirmedAt, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CreditMutationError) {
      return { error: `Could not create the override: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/commercial/accounts/${accountId}`);
  return { error: null };
}

export interface CheckCreditFormState {
  readonly error: string | null;
  readonly result: CreditCheckResult | null;
}

export async function checkCustomerCreditAction(tenantSlug: string, accountId: string, currency: string, requestedAmount: number, _prevState: CheckCreditFormState, _formData: FormData): Promise<CheckCreditFormState> {
  const access = await resolveCommercialAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Commercial workspace.", result: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const result = await checkCustomerCredit(supabase, { tenantId: access.tenant.id, accountId, currency, requestedAmount, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    return { error: null, result };
  } catch (error) {
    if (error instanceof CreditMutationError) {
      return { error: `Could not run the credit check: ${error.message}`, result: null };
    }
    throw error;
  }
}
