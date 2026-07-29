"use server";

/**
 * Receipt and Payment Allocation Server Actions (FIN-198, CG-S9-FIN-009).
 * Uses the RLS-scoped `authenticated` client -- every mutation is granted
 * directly to `authenticated` and performs its own FIN:Edit/FIN:Approve
 * authority check in-body, the same convention every prior capability's own
 * actions.ts uses.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveFinanceAccessForRequest } from "../../../../../lib/portal/resolve-finance-access.server.ts";
import { captureFinanceReceipt, allocateFinanceReceipt, requestFinanceReceiptDeallocation, ReceiptAllocationMutationError } from "../../../../../server/mutations/receipt-allocation.ts";

export interface FinanceReceiptFormState {
  readonly error: string | null;
}

export async function captureFinanceReceiptAction(
  tenantSlug: string,
  _prevState: FinanceReceiptFormState,
  formData: FormData,
): Promise<FinanceReceiptFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const customerAccountId = String(formData.get("customerAccountId") ?? "").trim();
  const receiptReference = String(formData.get("receiptReference") ?? "").trim();
  const receiptDate = String(formData.get("receiptDate") ?? "").trim();
  const payerName = String(formData.get("payerName") ?? "").trim();
  const bankAccountLabel = String(formData.get("bankAccountLabel") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const amount = Number(formData.get("amount") ?? "");
  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim();

  if (!customerAccountId || !receiptDate || !currency || !idempotencyKey) {
    return { error: "Customer account, receipt date, currency, and an idempotency key are required." };
  }
  if (!Number.isFinite(amount) || amount <= 0) {
    return { error: "Amount must be a positive number." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await captureFinanceReceipt(supabase, {
      tenantId: access.tenant.id,
      customerAccountId,
      receiptReference: receiptReference.length > 0 ? receiptReference : null,
      receiptDate,
      payerName: payerName.length > 0 ? payerName : null,
      bankAccountLabel: bankAccountLabel.length > 0 ? bankAccountLabel : null,
      currency,
      amount,
      idempotencyKey,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof ReceiptAllocationMutationError) {
      return { error: `Could not capture receipt: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/receipts`);
  return { error: null };
}

export async function allocateFinanceReceiptAction(
  tenantSlug: string,
  receiptId: string,
  _prevState: FinanceReceiptFormState,
  formData: FormData,
): Promise<FinanceReceiptFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const idempotencyKey = String(formData.get("idempotencyKey") ?? "").trim();
  const allocationsRaw = String(formData.get("allocations") ?? "").trim();

  if (!idempotencyKey || !allocationsRaw) {
    return { error: "An idempotency key and at least one allocation line are required." };
  }

  let allocations: Array<{ arOpenItemId: string; amount: number }>;
  try {
    const parsed = JSON.parse(allocationsRaw);
    if (!Array.isArray(parsed)) {
      throw new Error("not an array");
    }
    allocations = parsed.map((line: { arOpenItemId: string; amount: number }) => ({ arOpenItemId: line.arOpenItemId, amount: Number(line.amount) }));
  } catch {
    return { error: 'Allocations must be valid JSON, e.g. [{"arOpenItemId": "…", "amount": 100000}].' };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await allocateFinanceReceipt(supabase, { receiptId, idempotencyKey, allocations, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ReceiptAllocationMutationError) {
      return { error: `Could not allocate receipt: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/receipts`);
  return { error: null };
}

export async function requestFinanceReceiptDeallocationAction(
  tenantSlug: string,
  allocationId: string,
  _prevState: FinanceReceiptFormState,
  formData: FormData,
): Promise<FinanceReceiptFormState> {
  const access = await resolveFinanceAccessForRequest(tenantSlug);
  if (access.status !== "allowed") {
    return { error: "You don't have access to this organization's Finance workspace." };
  }

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A reason is required to reverse an allocation." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await requestFinanceReceiptDeallocation(supabase, { allocationId, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof ReceiptAllocationMutationError) {
      return { error: `Could not reverse allocation: ${error.message}` };
    }
    throw error;
  }

  revalidatePath(`/${tenantSlug}/finance/receipts`);
  return { error: null };
}
