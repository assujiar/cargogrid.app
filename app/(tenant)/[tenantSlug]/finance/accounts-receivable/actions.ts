"use server";

/**
 * Accounts Receivable Server Actions (FIN-196, CG-S9-FIN-007). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 * Open-item *creation* is not exposed here -- Prompt 196 section 24's own
 * "AR is created by a balanced source posting, never ad hoc UI entry except
 * approved migration/opening balance" -- only hold/release actions and the
 * exposure lookup are surfaced in this internal work-queue UI.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { placeFinanceArHold, releaseFinanceArHold, AccountsReceivableMutationError } from "../../../../../server/mutations/accounts-receivable.ts";
import { getFinanceArExposureSummary, AccountsReceivableQueryError } from "../../../../../server/queries/accounts-receivable.ts";
import type { FinanceArExposureSummary } from "../../../../../server/contracts/accounts-receivable/accounts-receivable.ts";

export interface FinanceArOpenItemFormState {
  readonly error: string | null;
}

export async function placeFinanceArHoldAction(
  tenantSlug: string,
  openItemId: string,
  expectedVersion: number,
  _prevState: FinanceArOpenItemFormState,
  formData: FormData,
): Promise<FinanceArOpenItemFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A reason is required to place a collection hold." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await placeFinanceArHold(supabase, { openItemId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AccountsReceivableMutationError) {
      return { error: `Could not place hold: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/accounts-receivable`);
  return { error: null };
}

export async function releaseFinanceArHoldAction(
  tenantSlug: string,
  openItemId: string,
  expectedVersion: number,
  _prevState: FinanceArOpenItemFormState,
  formData: FormData,
): Promise<FinanceArOpenItemFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await releaseFinanceArHold(supabase, { openItemId, expectedVersion, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof AccountsReceivableMutationError) {
      return { error: `Could not release hold: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/accounts-receivable`);
  return { error: null };
}

export interface FinanceArExposureLookupFormState {
  readonly error: string | null;
  readonly result: FinanceArExposureSummary | null;
}

export async function lookupFinanceArExposureAction(
  tenantSlug: string,
  _prevState: FinanceArExposureLookupFormState,
  formData: FormData,
): Promise<FinanceArExposureLookupFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace.", result: null };
  }

  const customerAccountId = String(formData.get("customerAccountId") ?? "").trim();
  if (!customerAccountId) {
    return { error: "A customer account ID is required.", result: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const result = await getFinanceArExposureSummary(supabase, { tenantId: access.tenant.id, customerAccountId, actorAuthUserId: access.authUserId });
    return { error: null, result };
  } catch (error) {
    if (error instanceof AccountsReceivableQueryError) {
      return { error: `Could not look up exposure: ${error.message}`, result: null };
    }
    throw error;
  }
}
