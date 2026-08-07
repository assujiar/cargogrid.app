"use server";

/**
 * Purchase Order Server Actions (PRC-260, CG-S11-PRC-011). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/vendor-comparison/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate) plus its own bound-per-row-action
 * convention (expectedVersion captured via `.bind()` at render time, not a hidden form
 * field).
 *
 * Idempotency-key disclosure: identical to every other PRC-25x creation form in this
 * repository -- a fresh `crypto.randomUUID()` is generated here, server-side, on every
 * submit, not client-persisted. The RPC-level idempotency guarantee itself is real and
 * tested (scripts/db-tests/procurement-purchase-order.sql).
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  draftPurchaseOrderFromSelection,
  submitPurchaseOrderForApproval,
  issuePurchaseOrder,
  acknowledgePurchaseOrder,
  recordPurchaseOrderFulfillmentStatus,
  amendPurchaseOrder,
  cancelPurchaseOrder,
  PurchaseOrderMutationError,
} from "../../../../../server/mutations/purchase-order.ts";

export interface PurchaseOrderActionState {
  readonly error: string | null;
}

const OK: PurchaseOrderActionState = { error: null };
const NO_ACCESS: PurchaseOrderActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function queuePath(tenantSlug: string): string {
  return `/${tenantSlug}/procurement/purchase-orders`;
}

function detailPath(tenantSlug: string, purchaseOrderId: string): string {
  return `/${tenantSlug}/procurement/purchase-orders/${purchaseOrderId}`;
}

// --- Creation (redirect to the new detail page on success) ----------------

export async function draftPurchaseOrderFromSelectionAction(tenantSlug: string, _prevState: PurchaseOrderActionState, formData: FormData): Promise<PurchaseOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const comparisonId = String(formData.get("comparisonId") ?? "").trim();
  if (!comparisonId) {
    return { error: "An approved, submitted vendor comparison id is required." };
  }
  const taxCode = String(formData.get("taxCode") ?? "").trim() || null;
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();
  const expectedDeliveryDate = String(formData.get("expectedDeliveryDate") ?? "").trim() || null;
  const servicePeriodStart = String(formData.get("servicePeriodStart") ?? "").trim() || null;
  const servicePeriodEnd = String(formData.get("servicePeriodEnd") ?? "").trim() || null;
  const commercialTerms = String(formData.get("commercialTerms") ?? "").trim() || null;
  const notes = String(formData.get("notes") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  let purchaseOrderId: string;
  try {
    const po = await draftPurchaseOrderFromSelection(supabase, {
      tenantId: access.tenant.id,
      comparisonId,
      taxCode,
      paymentTermDays: paymentTermDaysRaw.length > 0 ? Number(paymentTermDaysRaw) : null,
      expectedDeliveryDate,
      servicePeriodStart,
      servicePeriodEnd,
      commercialTerms,
      notes,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    purchaseOrderId = po.id;
  } catch (error) {
    if (error instanceof PurchaseOrderMutationError) return { error: `Could not draft the purchase order: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, purchaseOrderId));
}

// --- Detail-page lifecycle actions -----------------------------------------

export async function submitPurchaseOrderForApprovalAction(
  tenantSlug: string,
  purchaseOrderId: string,
  expectedVersion: number,
  _prevState: PurchaseOrderActionState,
  _formData: FormData,
): Promise<PurchaseOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitPurchaseOrderForApproval(supabase, { purchaseOrderId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PurchaseOrderMutationError) return { error: `Could not submit for approval: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, purchaseOrderId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function issuePurchaseOrderAction(
  tenantSlug: string,
  purchaseOrderId: string,
  expectedVersion: number,
  _prevState: PurchaseOrderActionState,
  _formData: FormData,
): Promise<PurchaseOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await issuePurchaseOrder(supabase, { purchaseOrderId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PurchaseOrderMutationError) return { error: `Could not issue: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, purchaseOrderId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function acknowledgePurchaseOrderAction(
  tenantSlug: string,
  purchaseOrderId: string,
  expectedVersion: number,
  _prevState: PurchaseOrderActionState,
  formData: FormData,
): Promise<PurchaseOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const acknowledgementNote = String(formData.get("acknowledgementNote") ?? "").trim();
  if (!acknowledgementNote) {
    return { error: "A non-empty acknowledgement note is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await acknowledgePurchaseOrder(supabase, { purchaseOrderId, expectedVersion, acknowledgementNote, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PurchaseOrderMutationError) return { error: `Could not record acknowledgement: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, purchaseOrderId));
  return OK;
}

export async function recordPurchaseOrderFulfillmentStatusAction(
  tenantSlug: string,
  purchaseOrderId: string,
  expectedVersion: number,
  _prevState: PurchaseOrderActionState,
  formData: FormData,
): Promise<PurchaseOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const fulfillmentStatusRaw = String(formData.get("fulfillmentStatus") ?? "");
  if (fulfillmentStatusRaw !== "partial" && fulfillmentStatusRaw !== "fulfilled") {
    return { error: "Fulfillment status must be partial or fulfilled." };
  }
  const fulfillmentReference = String(formData.get("fulfillmentReference") ?? "").trim();
  if (!fulfillmentReference) {
    return { error: "A non-empty fulfillment reference (canonical shipment/service evidence) is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await recordPurchaseOrderFulfillmentStatus(supabase, {
      purchaseOrderId,
      expectedVersion,
      fulfillmentStatus: fulfillmentStatusRaw,
      fulfillmentReference,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof PurchaseOrderMutationError) return { error: `Could not record fulfillment status: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, purchaseOrderId));
  return OK;
}

export async function amendPurchaseOrderAction(
  tenantSlug: string,
  purchaseOrderId: string,
  expectedVersion: number,
  _prevState: PurchaseOrderActionState,
  formData: FormData,
): Promise<PurchaseOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to amend a purchase order." };
  }
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();
  const expectedDeliveryDate = String(formData.get("expectedDeliveryDate") ?? "").trim() || null;
  const servicePeriodStart = String(formData.get("servicePeriodStart") ?? "").trim() || null;
  const servicePeriodEnd = String(formData.get("servicePeriodEnd") ?? "").trim() || null;
  const commercialTerms = String(formData.get("commercialTerms") ?? "").trim() || null;
  const notes = String(formData.get("notes") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  let newPurchaseOrderId: string;
  try {
    const po = await amendPurchaseOrder(supabase, {
      purchaseOrderId,
      expectedVersion,
      reason,
      idempotencyKey: crypto.randomUUID(),
      paymentTermDays: paymentTermDaysRaw.length > 0 ? Number(paymentTermDaysRaw) : null,
      expectedDeliveryDate,
      servicePeriodStart,
      servicePeriodEnd,
      commercialTerms,
      notes,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    newPurchaseOrderId = po.id;
  } catch (error) {
    if (error instanceof PurchaseOrderMutationError) return { error: `Could not amend: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, newPurchaseOrderId));
}

export async function cancelPurchaseOrderAction(
  tenantSlug: string,
  purchaseOrderId: string,
  expectedVersion: number,
  _prevState: PurchaseOrderActionState,
  formData: FormData,
): Promise<PurchaseOrderActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to cancel a purchase order." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelPurchaseOrder(supabase, { purchaseOrderId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof PurchaseOrderMutationError) return { error: `Could not cancel: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, purchaseOrderId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}
