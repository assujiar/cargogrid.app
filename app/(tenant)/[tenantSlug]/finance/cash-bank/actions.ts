"use server";

/**
 * Cash and Bank Baseline Server Actions (FIN-211, CG-S9-FIN-022). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly
 * to `authenticated` and performs its own FIN:Edit/FIN:Approve authority
 * check in-body, the same convention every prior capability's own
 * actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  createFinanceBankAccount,
  importFinanceBankStatement,
  matchFinanceBankTransaction,
  unmatchFinanceBankTransaction,
  CashBankMutationError,
} from "../../../../../server/mutations/cash-bank.ts";

export interface FinanceCashBankFormState {
  readonly error: string | null;
}

export async function createFinanceBankAccountAction(
  tenantSlug: string,
  _prevState: FinanceCashBankFormState,
  formData: FormData,
): Promise<FinanceCashBankFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const accountName = String(formData.get("accountName") ?? "").trim();
  const bankName = String(formData.get("bankName") ?? "").trim();
  const accountNumberLast4 = String(formData.get("accountNumberLast4") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const glAccountId = String(formData.get("glAccountId") ?? "").trim();

  if (!accountName || !bankName || !accountNumberLast4 || !currency || !glAccountId) {
    return { error: "Account name, bank name, last 4 digits, currency and GL account ID are all required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createFinanceBankAccount(supabase, {
      tenantId: access.tenant.id, accountName, bankName, accountNumberLast4, currency, glAccountId,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CashBankMutationError) {
      return { error: `Could not create bank account: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/cash-bank`);
  return { error: null };
}

export async function importFinanceBankStatementAction(
  tenantSlug: string,
  _prevState: FinanceCashBankFormState,
  formData: FormData,
): Promise<FinanceCashBankFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const bankAccountId = String(formData.get("bankAccountId") ?? "").trim();
  const sourceReference = String(formData.get("sourceReference") ?? "").trim();
  const linesRaw = String(formData.get("linesJson") ?? "").trim();

  if (!bankAccountId || !sourceReference || !linesRaw) {
    return { error: "Bank account ID, source reference and a lines JSON array are all required." };
  }

  let lines: unknown;
  try {
    lines = JSON.parse(linesRaw);
  } catch {
    return { error: 'Lines must be valid JSON, e.g. [{"transactionDate":"2026-07-01","direction":"credit","amount":500,"reference":"REF-1"}].' };
  }
  if (!Array.isArray(lines)) {
    return { error: "Lines must be a JSON array." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await importFinanceBankStatement(supabase, {
      tenantId: access.tenant.id, bankAccountId, sourceReference,
      lines: lines as { transactionDate: string; direction: "debit" | "credit"; amount: number; reference?: string | null; description?: string | null }[],
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CashBankMutationError) {
      return { error: `Could not import statement: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/cash-bank`);
  return { error: null };
}

export async function matchFinanceBankTransactionAction(
  tenantSlug: string,
  transactionId: string,
  expectedVersion: number,
  _prevState: FinanceCashBankFormState,
  formData: FormData,
): Promise<FinanceCashBankFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const matchedSourceType = String(formData.get("matchedSourceType") ?? "").trim();
  const matchedSourceIdRaw = String(formData.get("matchedSourceId") ?? "").trim();
  if (matchedSourceType !== "receipt" && matchedSourceType !== "settlement" && matchedSourceType !== "manual") {
    return { error: "Matched source type must be receipt, settlement or manual." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await matchFinanceBankTransaction(supabase, {
      transactionId, expectedVersion, matchedSourceType, matchedSourceId: matchedSourceIdRaw.length > 0 ? matchedSourceIdRaw : null,
      actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CashBankMutationError) {
      return { error: `Could not match transaction: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/cash-bank`);
  return { error: null };
}

export async function unmatchFinanceBankTransactionAction(
  tenantSlug: string,
  transactionId: string,
  expectedVersion: number,
  _prevState: FinanceCashBankFormState,
  formData: FormData,
): Promise<FinanceCashBankFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A reason is required to unmatch a transaction." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await unmatchFinanceBankTransaction(supabase, { transactionId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CashBankMutationError) {
      return { error: `Could not unmatch transaction: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/cash-bank`);
  return { error: null };
}
