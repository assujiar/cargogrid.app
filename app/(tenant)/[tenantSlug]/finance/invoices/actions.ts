"use server";

/**
 * Customer Invoice Server Actions (FIN-197, CG-S9-FIN-008). Uses the
 * RLS-scoped `authenticated` client -- every mutation is granted directly to
 * `authenticated` and performs its own FIN:Edit/FIN:Approve authority check
 * in-body, the same convention every prior capability's own actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import {
  prepareFinanceInvoiceFromReadiness,
  submitFinanceInvoiceForApproval,
  discardFinanceInvoiceDraft,
  approveFinanceInvoice,
  issueFinanceInvoice,
  InvoiceMutationError,
} from "../../../../../server/mutations/invoice.ts";

export interface FinanceInvoiceFormState {
  readonly error: string | null;
}

export async function prepareFinanceInvoiceFromReadinessAction(
  tenantSlug: string,
  _prevState: FinanceInvoiceFormState,
  formData: FormData,
): Promise<FinanceInvoiceFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const billingReadinessHandoffId = String(formData.get("billingReadinessHandoffId") ?? "").trim();
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "30").trim();
  const taxCode = String(formData.get("taxCode") ?? "").trim().toUpperCase();
  const paymentTermDays = Number(paymentTermDaysRaw);

  if (!billingReadinessHandoffId) {
    return { error: "A BillingReadinessHandoff ID is required." };
  }
  if (!Number.isFinite(paymentTermDays) || paymentTermDays < 0) {
    return { error: "Payment term days must be a non-negative number." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await prepareFinanceInvoiceFromReadiness(supabase, {
      tenantId: access.tenant.id,
      billingReadinessHandoffId,
      paymentTermDays,
      taxCode: taxCode.length > 0 ? taxCode : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof InvoiceMutationError) {
      return { error: `Could not prepare invoice: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/invoices`);
  return { error: null };
}

export async function submitFinanceInvoiceForApprovalAction(
  tenantSlug: string,
  invoiceId: string,
  expectedVersion: number,
  _prevState: FinanceInvoiceFormState,
  _formData: FormData,
): Promise<FinanceInvoiceFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await submitFinanceInvoiceForApproval(supabase, { invoiceId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof InvoiceMutationError) {
      return { error: `Could not submit invoice: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/invoices`);
  return { error: null };
}

export async function discardFinanceInvoiceDraftAction(
  tenantSlug: string,
  invoiceId: string,
  expectedVersion: number,
  _prevState: FinanceInvoiceFormState,
  formData: FormData,
): Promise<FinanceInvoiceFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await discardFinanceInvoiceDraft(supabase, { invoiceId, expectedVersion, reason: reason.length > 0 ? reason : null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof InvoiceMutationError) {
      return { error: `Could not discard invoice: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/invoices`);
  return { error: null };
}

export async function approveFinanceInvoiceAction(
  tenantSlug: string,
  invoiceId: string,
  expectedVersion: number,
  _prevState: FinanceInvoiceFormState,
  _formData: FormData,
): Promise<FinanceInvoiceFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await approveFinanceInvoice(supabase, { invoiceId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof InvoiceMutationError) {
      return { error: `Could not approve invoice: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/invoices`);
  return { error: null };
}

export async function issueFinanceInvoiceAction(
  tenantSlug: string,
  invoiceId: string,
  expectedVersion: number,
  _prevState: FinanceInvoiceFormState,
  formData: FormData,
): Promise<FinanceInvoiceFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const issueDate = String(formData.get("issueDate") ?? "").trim();
  if (!issueDate) {
    return { error: "An issue date is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await issueFinanceInvoice(supabase, { invoiceId, expectedVersion, issueDate, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof InvoiceMutationError) {
      return { error: `Could not issue invoice: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/invoices`);
  return { error: null };
}
