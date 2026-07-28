"use server";

/**
 * Chart of Accounts Server Actions (FIN-192, CG-S9-FIN-003). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Create/Edit/Approve/Delete
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { createFinanceAccountDraft, activateFinanceAccount, deactivateFinanceAccount, ChartOfAccountsMutationError } from "../../../../../server/mutations/chart-of-accounts.ts";
import { FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE, type FinanceAccountType } from "../../../../../server/contracts/chart-of-accounts/chart-of-accounts.ts";

export interface ChartOfAccountsFormState {
  readonly error: string | null;
}

export async function createFinanceAccountDraftAction(tenantSlug: string, _prevState: ChartOfAccountsFormState, formData: FormData): Promise<ChartOfAccountsFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const code = String(formData.get("code") ?? "").trim();
  const name = String(formData.get("name") ?? "").trim();
  const accountType = String(formData.get("accountType") ?? "") as FinanceAccountType;
  const parentAccountIdRaw = String(formData.get("parentAccountId") ?? "").trim();
  const isControlAccount = formData.get("isControlAccount") === "on";

  if (!code || !name) {
    return { error: "Code and name are required." };
  }
  const normalBalance = FINANCE_ACCOUNT_TYPE_NORMAL_BALANCE[accountType];
  if (!normalBalance) {
    return { error: "A valid account type is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createFinanceAccountDraft(supabase, {
      tenantId: access.tenant.id,
      code,
      name,
      accountType,
      normalBalance,
      parentAccountId: parentAccountIdRaw.length > 0 ? parentAccountIdRaw : null,
      isControlAccount,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ChartOfAccountsMutationError) {
      return { error: `Could not create account: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/chart-of-accounts`);
  return { error: null };
}

export async function activateFinanceAccountAction(
  tenantSlug: string,
  accountId: string,
  expectedVersion: number,
  _prevState: ChartOfAccountsFormState,
  _formData: FormData,
): Promise<ChartOfAccountsFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await activateFinanceAccount(supabase, { accountId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ChartOfAccountsMutationError) {
      return { error: `Could not activate: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/chart-of-accounts`);
  return { error: null };
}

export async function deactivateFinanceAccountAction(
  tenantSlug: string,
  accountId: string,
  expectedVersion: number,
  _prevState: ChartOfAccountsFormState,
  formData: FormData,
): Promise<ChartOfAccountsFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (reason.length === 0) {
    return { error: "A reason is required to deactivate an account." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await deactivateFinanceAccount(supabase, { accountId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ChartOfAccountsMutationError) {
      return { error: `Could not deactivate: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/chart-of-accounts`);
  return { error: null };
}
