"use server";

/**
 * Currency and Exchange Rate Server Actions (FIN-194, CG-S9-FIN-005). Uses
 * the RLS-scoped `authenticated` client -- every mutation is granted
 * directly to `authenticated` and performs its own FIN:Edit/FIN:Approve
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  createFinanceExchangeRateDraft,
  discardFinanceExchangeRateDraft,
  approveFinanceExchangeRate,
  CurrencyExchangeRateMutationError,
} from "../../../../../server/mutations/currency-exchange-rate.ts";
import { convertFinanceAmount, CurrencyExchangeRateQueryError } from "../../../../../server/queries/currency-exchange-rate.ts";
import type { FinanceConvertedAmount } from "../../../../../server/contracts/currency-exchange-rate/currency-exchange-rate.ts";

export interface FinanceExchangeRateFormState {
  readonly error: string | null;
}

export async function createFinanceExchangeRateDraftAction(
  tenantSlug: string,
  _prevState: FinanceExchangeRateFormState,
  formData: FormData,
): Promise<FinanceExchangeRateFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const sourceCurrency = String(formData.get("sourceCurrency") ?? "").trim().toUpperCase();
  const targetCurrency = String(formData.get("targetCurrency") ?? "").trim().toUpperCase();
  const rateType = String(formData.get("rateType") ?? "spot").trim() || "spot";
  const rate = Number(formData.get("rate") ?? "");
  const effectiveFrom = String(formData.get("effectiveFrom") ?? "").trim();
  const effectiveToRaw = String(formData.get("effectiveTo") ?? "").trim();

  if (!sourceCurrency || !targetCurrency || !effectiveFrom) {
    return { error: "Source currency, target currency, and an effective-from instant are required." };
  }
  if (!Number.isFinite(rate) || rate <= 0) {
    return { error: "Rate must be a positive number." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createFinanceExchangeRateDraft(supabase, {
      tenantId: access.tenant.id,
      rateType,
      sourceCurrency,
      targetCurrency,
      rate,
      effectiveFrom,
      effectiveTo: effectiveToRaw.length > 0 ? effectiveToRaw : null,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof CurrencyExchangeRateMutationError) {
      return { error: `Could not create draft rate: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/exchange-rates`);
  return { error: null };
}

export async function discardFinanceExchangeRateDraftAction(
  tenantSlug: string,
  rateId: string,
  expectedVersion: number,
  _prevState: FinanceExchangeRateFormState,
  _formData: FormData,
): Promise<FinanceExchangeRateFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceExchangeRateDraft(supabase, { rateId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CurrencyExchangeRateMutationError) {
      return { error: `Could not discard draft: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/exchange-rates`);
  return { error: null };
}

export async function approveFinanceExchangeRateAction(
  tenantSlug: string,
  rateId: string,
  expectedVersion: number,
  _prevState: FinanceExchangeRateFormState,
  _formData: FormData,
): Promise<FinanceExchangeRateFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinanceExchangeRate(supabase, { rateId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof CurrencyExchangeRateMutationError) {
      return { error: `Could not approve rate: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/exchange-rates`);
  return { error: null };
}

export interface ConvertFinanceAmountFormState {
  readonly error: string | null;
  readonly result: FinanceConvertedAmount | null;
}

export async function convertFinanceAmountAction(
  tenantSlug: string,
  _prevState: ConvertFinanceAmountFormState,
  formData: FormData,
): Promise<ConvertFinanceAmountFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace.", result: null };
  }

  const sourceCurrency = String(formData.get("sourceCurrency") ?? "").trim().toUpperCase();
  const targetCurrency = String(formData.get("targetCurrency") ?? "").trim().toUpperCase();
  const rateType = String(formData.get("rateType") ?? "spot").trim() || "spot";
  const amount = Number(formData.get("amount") ?? "");

  if (!sourceCurrency || !targetCurrency) {
    return { error: "Source and target currency are required.", result: null };
  }
  if (!Number.isFinite(amount)) {
    return { error: "Amount must be a number.", result: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const result = await convertFinanceAmount(supabase, {
      tenantId: access.tenant.id,
      amount,
      sourceCurrency,
      targetCurrency,
      rateType,
      asOf: null,
      actorAuthUserId: access.authUserId,
    });
    return { error: null, result };
  } catch (error) {
    if (error instanceof CurrencyExchangeRateQueryError) {
      return { error: `Could not convert: ${error.message}`, result: null };
    }
    throw error;
  }
}
