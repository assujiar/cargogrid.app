"use server";

/**
 * Self-service payroll Server Actions (HRT-282, CG-S12-HRT-010). Every
 * write here is self-only, structurally -- no employee-id parameter exists
 * on any of the create/submit/cancel RPCs this file calls (mirrors HRT-281's
 * own established anti-spoofing shape).
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveHrisAccessForRequest } from "../../../../../../lib/portal/resolve-hris-access.server.ts";
import {
  createPayrollReimbursementRequest,
  submitPayrollReimbursementRequest,
  cancelPayrollReimbursementRequest,
  PayrollMutationError,
} from "../../../../../../server/mutations/payroll.ts";

export interface MyPayrollActionState {
  readonly error: string | null;
}

const OK: MyPayrollActionState = { error: null };
const NO_ACCESS: MyPayrollActionState = { error: "You don't have access to this organization's HRIS workspace." };

function path(tenantSlug: string): string {
  return `/${tenantSlug}/hris/my/payroll`;
}

export async function createMyReimbursementRequestAction(tenantSlug: string, _prevState: MyPayrollActionState, formData: FormData): Promise<MyPayrollActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const category = String(formData.get("category") ?? "").trim();
  const amountRaw = String(formData.get("amount") ?? "").trim();
  const expenseDate = String(formData.get("expenseDate") ?? "").trim();
  const description = String(formData.get("description") ?? "").trim();
  const amount = Number(amountRaw);
  if (!category || !expenseDate || !description || !amountRaw || Number.isNaN(amount) || amount <= 0) {
    return { error: "Category, a positive amount, expense date, and description are all required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await createPayrollReimbursementRequest(supabase, {
      tenantId: access.tenant.id, category, amount, currency: "IDR", expenseDate, description, evidenceFileId: null,
      idempotencyKey: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not submit this reimbursement request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function submitMyReimbursementRequestAction(
  tenantSlug: string, requestId: string, expectedVersion: number, _prevState: MyPayrollActionState, _formData: FormData,
): Promise<MyPayrollActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitPayrollReimbursementRequest(supabase, { requestId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not submit this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}

export async function cancelMyReimbursementRequestAction(
  tenantSlug: string, requestId: string, expectedVersion: number, _prevState: MyPayrollActionState, formData: FormData,
): Promise<MyPayrollActionState> {
  const access = await resolveHrisAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) return { error: "A reason is required to cancel a reimbursement request." };

  const supabase = await createSupabaseServerClient();
  try {
    await cancelPayrollReimbursementRequest(supabase, { requestId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PayrollMutationError) return { error: `Could not cancel this request: ${error.message}` };
    throw error;
  }

  revalidatePath(path(tenantSlug));
  return OK;
}
