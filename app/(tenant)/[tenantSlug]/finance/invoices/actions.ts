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
import { issueFinanceCreditNote, FinanceCreditNoteMutationError } from "../../../../../server/mutations/finance-credit-note.ts";

export interface FinanceInvoiceFormState {
  readonly error: string | null;
}

/**
 * CG-AUDIT-2026-09-02 B7 (worklist half): `billingReadinessHandoffId` is now a
 * bound positional arg (the worklist's own per-row form binds it, the same
 * pattern every lifecycle action on this page already uses for `invoiceId`),
 * not a hand-typed FormData field -- closes "Invoicing is driven by a
 * hand-copied UUID."
 */
export async function prepareFinanceInvoiceFromReadinessAction(
  tenantSlug: string,
  billingReadinessHandoffId: string,
  _prevState: FinanceInvoiceFormState,
  formData: FormData,
): Promise<FinanceInvoiceFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "30").trim();
  const taxCode = String(formData.get("taxCode") ?? "").trim().toUpperCase();
  const paymentTermDays = Number(paymentTermDaysRaw);

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

/** CG-AUDIT-2026-09-02 B3: idempotencyKey is a bound positional arg generated once per page render (the same pattern this repository's own customer-portal-users page already established), so a double-click/network retry of the SAME form submission never posts a second AR reduction; a fresh page load gets a fresh key. */
export async function issueFinanceCreditNoteAction(
  tenantSlug: string,
  invoiceId: string,
  idempotencyKey: string,
  _prevState: FinanceInvoiceFormState,
  formData: FormData,
): Promise<FinanceInvoiceFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const amountRaw = String(formData.get("amount") ?? "").trim();
  const amount = Number(amountRaw);
  const reason = String(formData.get("reason") ?? "").trim();
  const creditDate = String(formData.get("creditDate") ?? "").trim();

  if (!Number.isFinite(amount) || amount <= 0) {
    return { error: "Enter a positive credit amount." };
  }
  if (!reason) {
    return { error: "A reason is required to issue a credit note." };
  }
  if (!creditDate) {
    return { error: "A credit date is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await issueFinanceCreditNote(supabase, { tenantId: access.tenant.id, invoiceId, amount, reason, creditDate, idempotencyKey, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof FinanceCreditNoteMutationError) {
      return { error: `Could not issue credit note: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/invoices`);
  return { error: null };
}
