"use server";

/**
 * Vendor Invoice Matching queue-page server actions (PRC-265, CG-S11-PRC-016).
 * Mirrors app/(tenant)/[tenantSlug]/procurement/vendor-contracts/actions.ts's own
 * shape: resolve portal access, call the typed mutation/query wrapper, translate a
 * known error into a plain-language message, revalidate/redirect.
 */

import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { getFinanceVendorBillLines, VendorBillQueryError } from "../../../../../server/queries/vendor-bill.ts";
import {
  createVendorBillMatchTolerancePolicyDraft,
  updateVendorBillMatchTolerancePolicyDraft,
  activateVendorBillMatchTolerancePolicy,
  VendorInvoiceMatchingMutationError,
} from "../../../../../server/mutations/vendor-invoice-matching.ts";

export interface VendorBillMatchQueueActionState {
  readonly error: string | null;
}

const OK: VendorBillMatchQueueActionState = { error: null };
const NO_ACCESS: VendorBillMatchQueueActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

/**
 * Starting a match case is a two-step flow (Prompt 265 §21's own "opens a match case,
 * maps lines" sequence needs the bill's real lines rendered before a caller can supply
 * vendor-stated figures per line) -- this action only validates the bill id resolves to
 * a real bill with at least one line, then redirects to the per-line input form. No
 * match case is created here.
 */
export async function startVendorBillMatchAction(tenantSlug: string, _prevState: VendorBillMatchQueueActionState, formData: FormData): Promise<VendorBillMatchQueueActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const billId = String(formData.get("billId") ?? "").trim();
  if (!billId) {
    return { error: "A vendor bill id is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    const lines = await getFinanceVendorBillLines(supabase, { billId, actorAuthUserId: access.authUserId });
    if (lines.length === 0) {
      return { error: "That bill has no lines to match." };
    }
  } catch (error) {
    if (error instanceof VendorBillQueryError) {
      return { error: `Could not load that bill: ${error.message}. Matching requires FIN:View in addition to your Procurement role -- ask your tenant admin if this persists.` };
    }
    throw error;
  }

  redirect(`/${tenantSlug}/procurement/vendor-invoice-matching/new/${billId}`);
}

export async function createVendorBillMatchTolerancePolicyDraftAction(tenantSlug: string, _prevState: VendorBillMatchQueueActionState, formData: FormData): Promise<VendorBillMatchQueueActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const name = String(formData.get("name") ?? "").trim();
  if (!name) {
    return { error: "A policy name is required." };
  }
  const quantityTolerancePct = Number(formData.get("quantityTolerancePct") ?? 0);
  const rateTolerancePct = Number(formData.get("rateTolerancePct") ?? 0);
  const taxTolerancePct = Number(formData.get("taxTolerancePct") ?? 0);
  const lineAmountToleranceAbs = Number(formData.get("lineAmountToleranceAbs") ?? 0);
  const autoClearEnabled = formData.get("autoClearEnabled") === "on";
  const duplicateWindowDaysRaw = String(formData.get("duplicateWindowDays") ?? "30").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await createVendorBillMatchTolerancePolicyDraft(supabase, {
      tenantId: access.tenant.id,
      name,
      quantityTolerancePct,
      rateTolerancePct,
      taxTolerancePct,
      lineAmountToleranceAbs,
      autoClearEnabled,
      duplicateWindowDays: duplicateWindowDaysRaw.length > 0 ? Number(duplicateWindowDaysRaw) : 30,
      notes: null,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not create the tolerance policy draft: ${error.message}` };
    throw error;
  }

  return OK;
}

export async function updateVendorBillMatchTolerancePolicyDraftAction(tenantSlug: string, _prevState: VendorBillMatchQueueActionState, formData: FormData): Promise<VendorBillMatchQueueActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const policyId = String(formData.get("policyId") ?? "").trim();
  const expectedVersion = Number(formData.get("expectedVersion") ?? 0);
  const name = String(formData.get("name") ?? "").trim();
  if (!policyId || !expectedVersion || !name) {
    return { error: "A policy id, expected version, and non-empty name are required." };
  }
  const quantityTolerancePct = Number(formData.get("quantityTolerancePct") ?? 0);
  const rateTolerancePct = Number(formData.get("rateTolerancePct") ?? 0);
  const taxTolerancePct = Number(formData.get("taxTolerancePct") ?? 0);
  const lineAmountToleranceAbs = Number(formData.get("lineAmountToleranceAbs") ?? 0);
  const autoClearEnabled = formData.get("autoClearEnabled") === "on";
  const duplicateWindowDaysRaw = String(formData.get("duplicateWindowDays") ?? "30").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await updateVendorBillMatchTolerancePolicyDraft(supabase, {
      policyId,
      expectedVersion,
      name,
      quantityTolerancePct,
      rateTolerancePct,
      taxTolerancePct,
      lineAmountToleranceAbs,
      autoClearEnabled,
      duplicateWindowDays: duplicateWindowDaysRaw.length > 0 ? Number(duplicateWindowDaysRaw) : 30,
      notes: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not update the draft: ${error.message}` };
    throw error;
  }

  return OK;
}

export async function activateVendorBillMatchTolerancePolicyAction(tenantSlug: string, _prevState: VendorBillMatchQueueActionState, formData: FormData): Promise<VendorBillMatchQueueActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const policyId = String(formData.get("policyId") ?? "").trim();
  const expectedVersion = Number(formData.get("expectedVersion") ?? 0);
  if (!policyId || !expectedVersion) {
    return { error: "A policy id and expected version are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await activateVendorBillMatchTolerancePolicy(supabase, { policyId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not activate: ${error.message}` };
    throw error;
  }

  return OK;
}
