"use server";

/**
 * Reversal and Adjustment Server Actions (FIN-206, CG-S9-FIN-017). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  prepareFinanceJournalReversal,
  prepareFinanceJournalAdjustment,
  submitFinanceCorrectionForApproval,
  discardFinanceCorrectionDraft,
  approveFinanceCorrection,
  postFinanceCorrection,
  JournalCorrectionMutationError,
} from "../../../../../server/mutations/journal-correction.ts";

export interface FinanceCorrectionFormState {
  readonly error: string | null;
}

export async function prepareFinanceJournalReversalAction(
  tenantSlug: string,
  _prevState: FinanceCorrectionFormState,
  formData: FormData,
): Promise<FinanceCorrectionFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const originalJournalId = String(formData.get("originalJournalId") ?? "").trim();
  const correctionDate = String(formData.get("correctionDate") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const evidenceRef = String(formData.get("evidenceRef") ?? "").trim();
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim();

  if (!originalJournalId) {
    return { error: "The original journal ID is required." };
  }
  if (!correctionDate) {
    return { error: "A correction date is required." };
  }
  if (!reason) {
    return { error: "A reason is required." };
  }
  if (!idempotencyKey) {
    return { error: "An idempotency key is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await prepareFinanceJournalReversal(supabase, {
      tenantId: access.tenant.id,
      originalJournalId,
      correctionDate,
      reason,
      evidenceRef: evidenceRef.length > 0 ? evidenceRef : null,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof JournalCorrectionMutationError) {
      return { error: `Could not prepare reversal: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/corrections`);
  return { error: null };
}

export async function prepareFinanceJournalAdjustmentAction(
  tenantSlug: string,
  _prevState: FinanceCorrectionFormState,
  formData: FormData,
): Promise<FinanceCorrectionFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const originalJournalId = String(formData.get("originalJournalId") ?? "").trim();
  const correctionDate = String(formData.get("correctionDate") ?? "").trim();
  const reason = String(formData.get("reason") ?? "").trim();
  const evidenceRef = String(formData.get("evidenceRef") ?? "").trim();
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim();
  const accountIds = String(formData.get("accountIds") ?? "").split(",").map((value) => value.trim()).filter((value) => value.length > 0);
  const directions = String(formData.get("directions") ?? "").split(",").map((value) => value.trim()).filter((value) => value.length > 0);
  const amounts = String(formData.get("amounts") ?? "").split(",").map((value) => value.trim()).filter((value) => value.length > 0);

  if (!originalJournalId || !correctionDate || !reason || !idempotencyKey) {
    return { error: "Original journal ID, correction date, reason, and idempotency key are all required." };
  }
  if (accountIds.length < 2 || accountIds.length !== directions.length || accountIds.length !== amounts.length) {
    return { error: "Provide at least two adjustment lines, each with a matching account ID, direction (debit/credit), and amount." };
  }

  const adjustmentLines: { accountId: string; direction: "debit" | "credit"; amount: number }[] = [];
  for (let index = 0; index < accountIds.length; index += 1) {
    const direction = directions[index];
    if (direction !== "debit" && direction !== "credit") {
      return { error: `Direction at position ${index + 1} must be "debit" or "credit".` };
    }
    const amount = Number(amounts[index]);
    if (!Number.isFinite(amount) || amount <= 0) {
      return { error: `Amount at position ${index + 1} must be a positive number.` };
    }
    adjustmentLines.push({ accountId: accountIds[index]!, direction, amount });
  }

  const supabase = await createSupabaseServerClient();
  try {
    await prepareFinanceJournalAdjustment(supabase, {
      tenantId: access.tenant.id,
      originalJournalId,
      correctionDate,
      reason,
      evidenceRef: evidenceRef.length > 0 ? evidenceRef : null,
      adjustmentLines,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof JournalCorrectionMutationError) {
      return { error: `Could not prepare adjustment: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/corrections`);
  return { error: null };
}

export async function submitFinanceCorrectionForApprovalAction(
  tenantSlug: string,
  correctionId: string,
  expectedVersion: number,
  _prevState: FinanceCorrectionFormState,
  _formData: FormData,
): Promise<FinanceCorrectionFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitFinanceCorrectionForApproval(supabase, { correctionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalCorrectionMutationError) {
      return { error: `Could not submit correction: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/corrections`);
  return { error: null };
}

export async function discardFinanceCorrectionDraftAction(
  tenantSlug: string,
  correctionId: string,
  expectedVersion: number,
  _prevState: FinanceCorrectionFormState,
  formData: FormData,
): Promise<FinanceCorrectionFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceCorrectionDraft(supabase, { correctionId, expectedVersion, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalCorrectionMutationError) {
      return { error: `Could not discard correction: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/corrections`);
  return { error: null };
}

export async function approveFinanceCorrectionAction(
  tenantSlug: string,
  correctionId: string,
  expectedVersion: number,
  _prevState: FinanceCorrectionFormState,
  _formData: FormData,
): Promise<FinanceCorrectionFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinanceCorrection(supabase, { correctionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalCorrectionMutationError) {
      return { error: `Could not approve correction: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/corrections`);
  return { error: null };
}

export async function postFinanceCorrectionAction(
  tenantSlug: string,
  correctionId: string,
  expectedVersion: number,
  _prevState: FinanceCorrectionFormState,
  _formData: FormData,
): Promise<FinanceCorrectionFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await postFinanceCorrection(supabase, { correctionId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof JournalCorrectionMutationError) {
      return { error: `Could not post correction: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/corrections`);
  return { error: null };
}
