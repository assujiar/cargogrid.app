"use server";

/**
 * Tax Baseline Server Actions (FIN-195, CG-S9-FIN-006). Uses the RLS-scoped
 * `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  createFinanceTaxRuleDraft,
  attachFinanceTaxRuleEvidence,
  discardFinanceTaxRuleDraft,
  approveFinanceTaxRule,
  TaxBaselineMutationError,
} from "../../../../../server/mutations/tax-baseline.ts";
import { calculateFinanceTax, TaxBaselineQueryError } from "../../../../../server/queries/tax-baseline.ts";
import type { FinanceTaxCalculation } from "../../../../../server/contracts/tax-baseline/tax-baseline.ts";

export interface FinanceTaxRuleFormState {
  readonly error: string | null;
}

export async function createFinanceTaxRuleDraftAction(
  tenantSlug: string,
  _prevState: FinanceTaxRuleFormState,
  formData: FormData,
): Promise<FinanceTaxRuleFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const taxCodeId = String(formData.get("taxCodeId") ?? "").trim();
  const rateBasis = String(formData.get("rateBasis") ?? "percentage").trim();
  const rateValue = Number(formData.get("rateValue") ?? "");
  const effectiveFrom = String(formData.get("effectiveFrom") ?? "").trim();

  if (!taxCodeId || !effectiveFrom) {
    return { error: "A tax code and an effective-from date are required." };
  }
  if (!Number.isFinite(rateValue) || rateValue < 0) {
    return { error: "Rate value must be a non-negative number." };
  }
  if (rateBasis !== "percentage" && rateBasis !== "fixed_amount") {
    return { error: "Rate basis must be percentage or fixed_amount." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createFinanceTaxRuleDraft(supabase, {
      tenantId: access.tenant.id,
      taxCodeId,
      rateBasis,
      rateValue,
      effectiveFrom,
      actorAuthUserId: access.authUserId,
      createdBy: access.authUserId,
    });
  } catch (error) {
    if (error instanceof TaxBaselineMutationError) {
      return { error: `Could not create draft rule: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/tax-baseline`);
  return { error: null };
}

export async function attachFinanceTaxRuleEvidenceAction(
  tenantSlug: string,
  ruleId: string,
  expectedVersion: number,
  _prevState: FinanceTaxRuleFormState,
  formData: FormData,
): Promise<FinanceTaxRuleFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const evidenceNote = String(formData.get("evidenceNote") ?? "").trim();
  if (!evidenceNote) {
    return { error: "An evidence note (or attached file) is required before a rule can be approved." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await attachFinanceTaxRuleEvidence(supabase, { ruleId, expectedVersion, evidenceNote, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TaxBaselineMutationError) {
      return { error: `Could not attach evidence: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/tax-baseline`);
  return { error: null };
}

export async function discardFinanceTaxRuleDraftAction(
  tenantSlug: string,
  ruleId: string,
  expectedVersion: number,
  _prevState: FinanceTaxRuleFormState,
  _formData: FormData,
): Promise<FinanceTaxRuleFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceTaxRuleDraft(supabase, { ruleId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TaxBaselineMutationError) {
      return { error: `Could not discard draft: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/tax-baseline`);
  return { error: null };
}

export async function approveFinanceTaxRuleAction(
  tenantSlug: string,
  ruleId: string,
  expectedVersion: number,
  _prevState: FinanceTaxRuleFormState,
  _formData: FormData,
): Promise<FinanceTaxRuleFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinanceTaxRule(supabase, { ruleId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof TaxBaselineMutationError) {
      return { error: `Could not approve rule: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/tax-baseline`);
  return { error: null };
}

export interface CalculateFinanceTaxFormState {
  readonly error: string | null;
  readonly result: FinanceTaxCalculation | null;
}

export async function calculateFinanceTaxAction(
  tenantSlug: string,
  _prevState: CalculateFinanceTaxFormState,
  formData: FormData,
): Promise<CalculateFinanceTaxFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace.", result: null };
  }

  const taxCode = String(formData.get("taxCode") ?? "").trim().toUpperCase();
  const baseAmount = Number(formData.get("baseAmount") ?? "");

  if (!taxCode) {
    return { error: "A tax code is required.", result: null };
  }
  if (!Number.isFinite(baseAmount) || baseAmount < 0) {
    return { error: "Base amount must be a non-negative number.", result: null };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const result = await calculateFinanceTax(supabase, { tenantId: access.tenant.id, taxCode, baseAmount, asOf: null, actorAuthUserId: access.authUserId });
    return { error: null, result };
  } catch (error) {
    if (error instanceof TaxBaselineQueryError) {
      return { error: `Could not calculate tax: ${error.message}`, result: null };
    }
    throw error;
  }
}
