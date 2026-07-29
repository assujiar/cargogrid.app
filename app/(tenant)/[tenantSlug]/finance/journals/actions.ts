"use server";

/**
 * Double-Entry Journal Server Actions (FIN-203, CG-S9-FIN-014). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 * Manual journal preparation only -- a system (subledger-sourced) journal is
 * never created from this UI, per Prompt 203 section 21/26's own "Accounting
 * prepares allowed manual journals."
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  createFinanceJournalDraft,
  submitFinanceJournalForApproval,
  discardFinanceJournalDraft,
  approveFinanceJournal,
  postFinanceJournal,
  JournalMutationError,
} from "../../../../../server/mutations/journal.ts";

export interface FinanceJournalFormState {
  readonly error: string | null;
}

export async function createFinanceJournalDraftAction(
  tenantSlug: string,
  _prevState: FinanceJournalFormState,
  formData: FormData,
): Promise<FinanceJournalFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const journalDate = String(formData.get("journalDate") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim();
  const accountIds = String(formData.get("accountIds") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  const directions = String(formData.get("directions") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  const amounts = String(formData.get("amounts") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);

  if (!journalDate) {
    return { error: "A journal date is required." };
  }
  if (!currency) {
    return { error: "A currency is required." };
  }
  if (!idempotencyKey) {
    return { error: "An idempotency key is required." };
  }
  if (accountIds.length < 2 || accountIds.length !== directions.length || accountIds.length !== amounts.length) {
    return { error: "Provide at least two lines, each with a matching account ID, direction (debit/credit), and amount." };
  }

  const lines: { accountId: string; direction: "debit" | "credit"; amount: number }[] = [];
  for (let index = 0; index < accountIds.length; index += 1) {
    const direction = directions[index];
    if (direction !== "debit" && direction !== "credit") {
      return { error: `Direction at position ${index + 1} must be "debit" or "credit".` };
    }
    const amount = Number(amounts[index]);
    if (!Number.isFinite(amount) || amount <= 0) {
      return { error: `Amount at position ${index + 1} must be a positive number.` };
    }
    lines.push({ accountId: accountIds[index]!, direction, amount });
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createFinanceJournalDraft(supabase, {
      tenantId: access.tenant.id,
      journalDate,
      currency,
      lines,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof JournalMutationError) {
      return { error: `Could not prepare journal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/journals`);
  return { error: null };
}

export async function submitFinanceJournalForApprovalAction(
  tenantSlug: string,
  journalId: string,
  expectedVersion: number,
  _prevState: FinanceJournalFormState,
  _formData: FormData,
): Promise<FinanceJournalFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitFinanceJournalForApproval(supabase, { journalId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalMutationError) {
      return { error: `Could not submit journal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/journals`);
  return { error: null };
}

export async function discardFinanceJournalDraftAction(
  tenantSlug: string,
  journalId: string,
  expectedVersion: number,
  _prevState: FinanceJournalFormState,
  formData: FormData,
): Promise<FinanceJournalFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceJournalDraft(supabase, { journalId, expectedVersion, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalMutationError) {
      return { error: `Could not discard journal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/journals`);
  return { error: null };
}

export async function approveFinanceJournalAction(
  tenantSlug: string,
  journalId: string,
  expectedVersion: number,
  _prevState: FinanceJournalFormState,
  _formData: FormData,
): Promise<FinanceJournalFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinanceJournal(supabase, { journalId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalMutationError) {
      return { error: `Could not approve journal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/journals`);
  return { error: null };
}

export async function postFinanceJournalAction(
  tenantSlug: string,
  journalId: string,
  expectedVersion: number,
  _prevState: FinanceJournalFormState,
  _formData: FormData,
): Promise<FinanceJournalFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await postFinanceJournal(supabase, { journalId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalMutationError) {
      return { error: `Could not post journal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/journals`);
  return { error: null };
}
