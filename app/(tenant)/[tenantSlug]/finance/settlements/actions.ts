"use server";

/**
 * Settlement Server Actions (FIN-201, CG-S9-FIN-012). Uses the RLS-scoped
 * `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  prepareFinanceSettlement,
  submitFinanceSettlementForApproval,
  discardFinanceSettlementDraft,
  approveFinanceSettlement,
  executeFinanceSettlement,
  postFinanceSettlement,
  requestFinanceSettlementReversal,
  SettlementMutationError,
} from "../../../../../server/mutations/settlement.ts";

export interface FinanceSettlementFormState {
  readonly error: string | null;
}

export async function prepareFinanceSettlementAction(
  tenantSlug: string,
  _prevState: FinanceSettlementFormState,
  formData: FormData,
): Promise<FinanceSettlementFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  const paymentReference = String(formData.get("paymentReference") ?? "").trim();
  const bankAccountLabel = String(formData.get("bankAccountLabel") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const settlementDate = String(formData.get("settlementDate") ?? "").trim();
  const feeAmountRaw = String(formData.get("feeAmount") ?? "0").trim();
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim();
  const apOpenItemIds = String(formData.get("apOpenItemIds") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  const amounts = String(formData.get("amounts") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);

  if (!vendorMasterId) {
    return { error: "A vendor master ID is required." };
  }
  if (!currency) {
    return { error: "A currency is required." };
  }
  if (!settlementDate) {
    return { error: "A settlement date is required." };
  }
  if (!idempotencyKey) {
    return { error: "An idempotency key is required." };
  }
  if (apOpenItemIds.length === 0 || apOpenItemIds.length !== amounts.length) {
    return { error: "Provide a matching AP open item ID and amount for every allocation line." };
  }
  const feeAmount = Number(feeAmountRaw);
  if (!Number.isFinite(feeAmount) || feeAmount < 0) {
    return { error: "Fee amount must be a non-negative number." };
  }

  const allocations: { apOpenItemId: string; amount: number }[] = [];
  for (let index = 0; index < apOpenItemIds.length; index += 1) {
    const amount = Number(amounts[index]);
    if (!Number.isFinite(amount) || amount <= 0) {
      return { error: `Allocation amount at position ${index + 1} must be a positive number.` };
    }
    allocations.push({ apOpenItemId: apOpenItemIds[index]!, amount });
  }

  const supabase = await createSupabaseServerClient();
  try {
    await prepareFinanceSettlement(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      paymentReference: paymentReference.length > 0 ? paymentReference : null,
      bankAccountLabel: bankAccountLabel.length > 0 ? bankAccountLabel : null,
      currency,
      settlementDate,
      allocations,
      feeAmount,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SettlementMutationError) {
      return { error: `Could not prepare settlement: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/settlements`);
  return { error: null };
}

export async function submitFinanceSettlementForApprovalAction(
  tenantSlug: string,
  settlementId: string,
  expectedVersion: number,
  _prevState: FinanceSettlementFormState,
  _formData: FormData,
): Promise<FinanceSettlementFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitFinanceSettlementForApproval(supabase, { settlementId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SettlementMutationError) {
      return { error: `Could not submit settlement: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/settlements`);
  return { error: null };
}

export async function discardFinanceSettlementDraftAction(
  tenantSlug: string,
  settlementId: string,
  expectedVersion: number,
  _prevState: FinanceSettlementFormState,
  formData: FormData,
): Promise<FinanceSettlementFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceSettlementDraft(supabase, { settlementId, expectedVersion, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SettlementMutationError) {
      return { error: `Could not discard settlement: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/settlements`);
  return { error: null };
}

export async function approveFinanceSettlementAction(
  tenantSlug: string,
  settlementId: string,
  expectedVersion: number,
  _prevState: FinanceSettlementFormState,
  _formData: FormData,
): Promise<FinanceSettlementFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinanceSettlement(supabase, { settlementId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SettlementMutationError) {
      return { error: `Could not approve settlement: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/settlements`);
  return { error: null };
}

export async function executeFinanceSettlementAction(
  tenantSlug: string,
  settlementId: string,
  expectedVersion: number,
  _prevState: FinanceSettlementFormState,
  formData: FormData,
): Promise<FinanceSettlementFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const executionReference = String(formData.get("executionReference") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await executeFinanceSettlement(supabase, {
      settlementId,
      expectedVersion,
      executionReference: executionReference.length > 0 ? executionReference : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof SettlementMutationError) {
      return { error: `Could not record settlement execution: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/settlements`);
  return { error: null };
}

export async function postFinanceSettlementAction(
  tenantSlug: string,
  settlementId: string,
  expectedVersion: number,
  _prevState: FinanceSettlementFormState,
  _formData: FormData,
): Promise<FinanceSettlementFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await postFinanceSettlement(supabase, { settlementId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SettlementMutationError) {
      return { error: `Could not post settlement: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/settlements`);
  return { error: null };
}

export async function requestFinanceSettlementReversalAction(
  tenantSlug: string,
  settlementId: string,
  _prevState: FinanceSettlementFormState,
  formData: FormData,
): Promise<FinanceSettlementFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to reverse a posted settlement." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await requestFinanceSettlementReversal(supabase, { settlementId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof SettlementMutationError) {
      return { error: `Could not reverse settlement: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/settlements`);
  return { error: null };
}
