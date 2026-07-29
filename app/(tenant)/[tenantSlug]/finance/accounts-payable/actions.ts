"use server";

/**
 * Accounts Payable Server Actions (FIN-199, CG-S9-FIN-010). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 * Open-item *creation* is not exposed here -- Prompt 199 section 24's own "AP
 * is created through controlled bill posting, not arbitrary balance entry
 * except approved migration" -- only hold/release actions and the exposure
 * lookup are surfaced in this internal work-queue UI.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { placeFinanceApHold, releaseFinanceApHold, AccountsPayableMutationError } from "../../../../../server/mutations/accounts-payable.ts";
import { getFinanceApExposureSummary, AccountsPayableQueryError } from "../../../../../server/queries/accounts-payable.ts";
import type { FinanceApExposureSummary } from "../../../../../server/contracts/accounts-payable/accounts-payable.ts";

export interface FinanceApOpenItemFormState {
  readonly error: string | null;
}

export async function placeFinanceApHoldAction(
  tenantSlug: string,
  openItemId: string,
  expectedVersion: number,
  _prevState: FinanceApOpenItemFormState,
  formData: FormData,
): Promise<FinanceApOpenItemFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A reason is required to place a payment hold." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await placeFinanceApHold(supabase, { openItemId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AccountsPayableMutationError) {
      return { error: `Could not place hold: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/accounts-payable`);
  return { error: null };
}

export async function releaseFinanceApHoldAction(
  tenantSlug: string,
  openItemId: string,
  expectedVersion: number,
  _prevState: FinanceApOpenItemFormState,
  formData: FormData,
): Promise<FinanceApOpenItemFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await releaseFinanceApHold(supabase, { openItemId, expectedVersion, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AccountsPayableMutationError) {
      return { error: `Could not release hold: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/accounts-payable`);
  return { error: null };
}

export interface FinanceApExposureLookupFormState {
  readonly error: string | null;
  readonly result: FinanceApExposureSummary | null;
}

export async function lookupFinanceApExposureAction(
  tenantSlug: string,
  _prevState: FinanceApExposureLookupFormState,
  formData: FormData,
): Promise<FinanceApExposureLookupFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace.", result: null };
  }

  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  if (!vendorMasterId) {
    return { error: "A vendor reference ID is required.", result: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const result = await getFinanceApExposureSummary(supabase, { tenantId: access.tenant.id, vendorMasterId, actorAuthUserId: access.authUserId });
    return { error: null, result };
  } catch (error) {
    if (error instanceof AccountsPayableQueryError) {
      return { error: `Could not look up exposure: ${error.message}`, result: null };
    }
    throw error;
  }
}
