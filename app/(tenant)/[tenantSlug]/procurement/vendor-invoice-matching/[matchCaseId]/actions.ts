"use server";

/**
 * Vendor Invoice Matching detail-page server actions (PRC-265, CG-S11-PRC-016).
 * Mirrors app/(tenant)/[tenantSlug]/procurement/vendor-contracts/[contractId]/actions.ts's
 * own shape.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  reEvaluateVendorBillMatchCase,
  mapVendorBillMatchLine,
  acceptVendorBillMatchWithinTolerance,
  cancelVendorBillMatchCase,
  raiseVendorBillMatchDispute,
  recordVendorBillMatchDisputeResponse,
  resolveVendorBillMatchDispute,
  requestVendorBillMatchExceptionApproval,
  decideVendorBillMatchExceptionApproval,
  VendorInvoiceMatchingMutationError,
} from "../../../../../../server/mutations/vendor-invoice-matching.ts";

export interface VendorBillMatchDetailActionState {
  readonly error: string | null;
}

const OK: VendorBillMatchDetailActionState = { error: null };
const NO_ACCESS: VendorBillMatchDetailActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function detailPath(tenantSlug: string, matchCaseId: string): string {
  return `/${tenantSlug}/procurement/vendor-invoice-matching/${matchCaseId}`;
}

export async function reEvaluateVendorBillMatchCaseAction(
  tenantSlug: string,
  matchCaseId: string,
  expectedVersion: number,
  lineIds: readonly string[],
  _prevState: VendorBillMatchDetailActionState,
  formData: FormData,
): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const purchaseOrderIdRaw = String(formData.get("purchaseOrderId") ?? "").trim();
  const lineInputs = lineIds.map((lineId) => {
    const amountRaw = String(formData.get(`amount_${lineId}`) ?? "").trim();
    const quantityRaw = String(formData.get(`quantity_${lineId}`) ?? "").trim();
    const rateRaw = String(formData.get(`rate_${lineId}`) ?? "").trim();
    const uomRaw = String(formData.get(`uom_${lineId}`) ?? "").trim();
    return {
      billLineId: lineId,
      vendorStatedAmount: Number(amountRaw),
      vendorStatedQuantity: quantityRaw.length > 0 ? Number(quantityRaw) : null,
      vendorStatedRate: rateRaw.length > 0 ? Number(rateRaw) : null,
      vendorStatedUom: uomRaw.length > 0 ? uomRaw : null,
    };
  });
  if (lineInputs.some((l) => Number.isNaN(l.vendorStatedAmount))) {
    return { error: "Every line requires a valid vendor-stated amount." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await reEvaluateVendorBillMatchCase(supabase, {
      matchCaseId,
      expectedVersion,
      purchaseOrderId: purchaseOrderIdRaw.length > 0 ? purchaseOrderIdRaw : null,
      lineInputs,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not re-evaluate: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function mapVendorBillMatchLineAction(tenantSlug: string, matchCaseId: string, _prevState: VendorBillMatchDetailActionState, formData: FormData): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const matchLineId = String(formData.get("matchLineId") ?? "").trim();
  const expectedCaseVersion = Number(formData.get("expectedCaseVersion") ?? 0);
  const poLineIdRaw = String(formData.get("poLineId") ?? "").trim();
  const rateVersionIdRaw = String(formData.get("rateVersionId") ?? "").trim();
  if (!matchLineId || !expectedCaseVersion) {
    return { error: "A match line id and expected case version are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await mapVendorBillMatchLine(supabase, {
      matchLineId,
      expectedCaseVersion,
      poLineId: poLineIdRaw.length > 0 ? poLineIdRaw : null,
      rateVersionId: rateVersionIdRaw.length > 0 ? rateVersionIdRaw : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not map the line: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function acceptVendorBillMatchWithinToleranceAction(
  tenantSlug: string,
  matchCaseId: string,
  expectedVersion: number,
  _prevState: VendorBillMatchDetailActionState,
  _formData: FormData,
): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await acceptVendorBillMatchWithinTolerance(supabase, { matchCaseId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not accept: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function cancelVendorBillMatchCaseAction(
  tenantSlug: string,
  matchCaseId: string,
  expectedVersion: number,
  _prevState: VendorBillMatchDetailActionState,
  formData: FormData,
): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to cancel a match case." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelVendorBillMatchCase(supabase, { matchCaseId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not cancel: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function raiseVendorBillMatchDisputeAction(tenantSlug: string, matchCaseId: string, _prevState: VendorBillMatchDetailActionState, formData: FormData): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to raise a dispute." };
  }
  const matchLineIdRaw = String(formData.get("matchLineId") ?? "").trim();
  const disputedAmountRaw = String(formData.get("disputedAmount") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await raiseVendorBillMatchDispute(supabase, {
      matchCaseId,
      matchLineId: matchLineIdRaw.length > 0 ? matchLineIdRaw : null,
      reason,
      disputedAmount: disputedAmountRaw.length > 0 ? Number(disputedAmountRaw) : null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not raise the dispute: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function recordVendorBillMatchDisputeResponseAction(tenantSlug: string, matchCaseId: string, _prevState: VendorBillMatchDetailActionState, formData: FormData): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const disputeId = String(formData.get("disputeId") ?? "").trim();
  const expectedVersion = Number(formData.get("expectedVersion") ?? 0);
  const vendorResponse = String(formData.get("vendorResponse") ?? "").trim();
  if (!disputeId || !expectedVersion || !vendorResponse) {
    return { error: "A dispute id, expected version, and non-empty response are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await recordVendorBillMatchDisputeResponse(supabase, { disputeId, expectedVersion, vendorResponse, vendorResponseFileId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not record the response: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function resolveVendorBillMatchDisputeAction(tenantSlug: string, matchCaseId: string, _prevState: VendorBillMatchDetailActionState, formData: FormData): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const disputeId = String(formData.get("disputeId") ?? "").trim();
  const expectedVersion = Number(formData.get("expectedVersion") ?? 0);
  const decisionRaw = String(formData.get("decision") ?? "").trim();
  const resolutionNote = String(formData.get("resolutionNote") ?? "").trim();
  if (!disputeId || !expectedVersion || !resolutionNote || !["upheld", "rejected", "withdrawn"].includes(decisionRaw)) {
    return { error: "A dispute id, expected version, a valid decision, and a non-empty resolution note are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await resolveVendorBillMatchDispute(supabase, {
      disputeId,
      expectedVersion,
      decision: decisionRaw as "upheld" | "rejected" | "withdrawn",
      resolutionNote,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not resolve the dispute: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function requestVendorBillMatchExceptionApprovalAction(
  tenantSlug: string,
  matchCaseId: string,
  expectedVersion: number,
  _prevState: VendorBillMatchDetailActionState,
  formData: FormData,
): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to request exception approval." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await requestVendorBillMatchExceptionApproval(supabase, { matchCaseId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not request exception approval: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}

export async function decideVendorBillMatchExceptionApprovalAction(tenantSlug: string, matchCaseId: string, _prevState: VendorBillMatchDetailActionState, formData: FormData): Promise<VendorBillMatchDetailActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const approvalId = String(formData.get("approvalId") ?? "").trim();
  const expectedVersion = Number(formData.get("expectedVersion") ?? 0);
  const decisionRaw = String(formData.get("decision") ?? "").trim();
  const decisionNote = String(formData.get("decisionNote") ?? "").trim();
  if (!approvalId || !expectedVersion || !decisionNote || !["approved", "rejected"].includes(decisionRaw)) {
    return { error: "An approval id, expected version, a valid decision, and a non-empty decision note are required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await decideVendorBillMatchExceptionApproval(supabase, {
      approvalId,
      expectedVersion,
      decision: decisionRaw as "approved" | "rejected",
      decisionNote,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorInvoiceMatchingMutationError) return { error: `Could not decide the exception approval: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, matchCaseId));
  return OK;
}
