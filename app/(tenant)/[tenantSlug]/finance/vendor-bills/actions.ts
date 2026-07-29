"use server";

/**
 * Vendor Bill Server Actions (FIN-200, CG-S9-FIN-011). Uses the RLS-scoped
 * `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  prepareFinanceVendorBillFromActualCost,
  submitFinanceVendorBillForApproval,
  discardFinanceVendorBillDraft,
  approveFinanceVendorBill,
  postFinanceVendorBill,
  VendorBillMutationError,
} from "../../../../../server/mutations/vendor-bill.ts";

export interface FinanceVendorBillFormState {
  readonly error: string | null;
}

export async function prepareFinanceVendorBillFromActualCostAction(
  tenantSlug: string,
  _prevState: FinanceVendorBillFormState,
  formData: FormData,
): Promise<FinanceVendorBillFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const actualCostId = String(formData.get("actualCostId") ?? "").trim();
  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  const vendorReference = String(formData.get("vendorReference") ?? "").trim();
  const billDate = String(formData.get("billDate") ?? "").trim();
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "30").trim();
  const vendorStatedAmountRaw = String(formData.get("vendorStatedAmount") ?? "").trim();
  const taxCode = String(formData.get("taxCode") ?? "").trim().toUpperCase();
  const paymentTermDays = Number(paymentTermDaysRaw);

  if (!actualCostId) {
    return { error: "An actual cost ID is required." };
  }
  if (!vendorMasterId) {
    return { error: "A vendor master ID is required." };
  }
  if (!billDate) {
    return { error: "A bill date is required." };
  }
  if (!Number.isFinite(paymentTermDays) || paymentTermDays < 0) {
    return { error: "Payment term days must be a non-negative number." };
  }
  let vendorStatedAmount: number | null = null;
  if (vendorStatedAmountRaw.length > 0) {
    vendorStatedAmount = Number(vendorStatedAmountRaw);
    if (!Number.isFinite(vendorStatedAmount)) {
      return { error: "Vendor-stated amount must be a number." };
    }
  }

  const supabase = await createSupabaseServerClient();
  try {
    await prepareFinanceVendorBillFromActualCost(supabase, {
      tenantId: access.tenant.id,
      actualCostId,
      vendorMasterId,
      vendorReference: vendorReference.length > 0 ? vendorReference : null,
      billDate,
      paymentTermDays,
      vendorStatedAmount,
      taxCode: taxCode.length > 0 ? taxCode : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorBillMutationError) {
      return { error: `Could not prepare vendor bill: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/vendor-bills`);
  return { error: null };
}

export async function submitFinanceVendorBillForApprovalAction(
  tenantSlug: string,
  billId: string,
  expectedVersion: number,
  _prevState: FinanceVendorBillFormState,
  _formData: FormData,
): Promise<FinanceVendorBillFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitFinanceVendorBillForApproval(supabase, { billId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorBillMutationError) {
      return { error: `Could not submit vendor bill: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/vendor-bills`);
  return { error: null };
}

export async function discardFinanceVendorBillDraftAction(
  tenantSlug: string,
  billId: string,
  expectedVersion: number,
  _prevState: FinanceVendorBillFormState,
  formData: FormData,
): Promise<FinanceVendorBillFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceVendorBillDraft(supabase, { billId, expectedVersion, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorBillMutationError) {
      return { error: `Could not discard vendor bill: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/vendor-bills`);
  return { error: null };
}

export async function approveFinanceVendorBillAction(
  tenantSlug: string,
  billId: string,
  expectedVersion: number,
  _prevState: FinanceVendorBillFormState,
  _formData: FormData,
): Promise<FinanceVendorBillFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinanceVendorBill(supabase, { billId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorBillMutationError) {
      return { error: `Could not approve vendor bill: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/vendor-bills`);
  return { error: null };
}

export async function postFinanceVendorBillAction(
  tenantSlug: string,
  billId: string,
  expectedVersion: number,
  _prevState: FinanceVendorBillFormState,
  _formData: FormData,
): Promise<FinanceVendorBillFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await postFinanceVendorBill(supabase, { billId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorBillMutationError) {
      return { error: `Could not post vendor bill: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/vendor-bills`);
  return { error: null };
}
