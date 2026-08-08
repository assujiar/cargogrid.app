"use server";

/**
 * Vendor Contract Server Actions (PRC-261, CG-S11-PRC-012). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/purchase-orders/actions.ts's own exact shape
 * (resolve portal access, call the typed mutation wrapper, translate a known mutation
 * error into a plain-language message, revalidate) plus its own bound-per-row-action
 * convention (expectedVersion captured via `.bind()` at render time, not a hidden form
 * field). Approval decisions are NOT here -- they dispatch from the shared
 * /procurement/approvals inbox (decideProcurementApprovalStepAction), mirroring
 * purchase_order's own identical split.
 *
 * Idempotency-key disclosure: identical to every other PRC-25x/26x creation form in
 * this repository -- a fresh crypto.randomUUID() is generated here, server-side, on
 * every submit, not client-persisted. The RPC-level idempotency guarantee itself is
 * real and tested (scripts/db-tests/procurement-vendor-contract.sql).
 */

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { createSupabaseServerClient } from "../../../../../lib/supabase/server.ts";
import { resolveProcurementAccessForRequest } from "../../../../../lib/portal/resolve-procurement-access.server.ts";
import { VENDOR_CONTRACT_TYPES } from "../../../../../server/contracts/vendor-contract/vendor-contract.ts";
import {
  createVendorContractDraft,
  updateVendorContractDraft,
  submitVendorContractForApproval,
  recordVendorContractSignature,
  activateVendorContract,
  amendVendorContract,
  renewVendorContract,
  suspendVendorContract,
  reactivateVendorContract,
  terminateVendorContract,
  cancelVendorContractDraft,
  VendorContractMutationError,
} from "../../../../../server/mutations/vendor-contract.ts";

export interface VendorContractActionState {
  readonly error: string | null;
}

const OK: VendorContractActionState = { error: null };
const NO_ACCESS: VendorContractActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

function queuePath(tenantSlug: string): string {
  return `/${tenantSlug}/procurement/vendor-contracts`;
}

function detailPath(tenantSlug: string, contractId: string): string {
  return `/${tenantSlug}/procurement/vendor-contracts/${contractId}`;
}

// --- Creation (redirect to the new detail page on success) ----------------

export async function createVendorContractDraftAction(tenantSlug: string, _prevState: VendorContractActionState, formData: FormData): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const vendorMasterId = String(formData.get("vendorMasterId") ?? "").trim();
  if (!vendorMasterId) {
    return { error: "An active vendor is required." };
  }
  const contractTypeRaw = String(formData.get("contractType") ?? "fixed_term").trim();
  if (!(VENDOR_CONTRACT_TYPES as readonly string[]).includes(contractTypeRaw)) {
    return { error: "Contract type must be framework or fixed_term." };
  }
  const contractType = contractTypeRaw as (typeof VENDOR_CONTRACT_TYPES)[number];
  const effectiveStart = String(formData.get("effectiveStart") ?? "").trim();
  if (!effectiveStart) {
    return { error: "An effective start date is required." };
  }
  const effectiveEnd = String(formData.get("effectiveEnd") ?? "").trim() || null;
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  let contractId: string;
  try {
    const contract = await createVendorContractDraft(supabase, {
      tenantId: access.tenant.id,
      vendorMasterId,
      contractType,
      effectiveStart,
      effectiveEnd,
      rateVersionId: null,
      paymentTermDays: paymentTermDaysRaw.length > 0 ? Number(paymentTermDaysRaw) : null,
      taxTerms: {},
      slaTerms: {},
      capacityTerms: {},
      coverageTerms: {},
      complianceRequired: [],
      signatureRequired: true,
      idempotencyKey: crypto.randomUUID(),
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    contractId = contract.id;
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not create the draft contract: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, contractId));
}

// --- Detail-page lifecycle actions -----------------------------------------

export async function updateVendorContractDraftAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const effectiveStart = String(formData.get("effectiveStart") ?? "").trim();
  if (!effectiveStart) {
    return { error: "An effective start date is required." };
  }
  const effectiveEnd = String(formData.get("effectiveEnd") ?? "").trim() || null;
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  try {
    await updateVendorContractDraft(supabase, {
      contractId,
      expectedVersion,
      effectiveStart,
      effectiveEnd,
      rateVersionId: null,
      paymentTermDays: paymentTermDaysRaw.length > 0 ? Number(paymentTermDaysRaw) : null,
      // This form only edits effectiveStart/effectiveEnd/paymentTermDays -- the
      // remaining *Terms/complianceRequired fields are left null (unchanged), never
      // reset to {}/[] (see the schema's own header comment on why that distinction
      // is load-bearing).
      taxTerms: null,
      slaTerms: null,
      capacityTerms: null,
      coverageTerms: null,
      complianceRequired: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not update the draft: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  return OK;
}

export async function submitVendorContractForApprovalAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  _formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await submitVendorContractForApproval(supabase, { contractId, expectedVersion, idempotencyKey: crypto.randomUUID(), actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not submit for approval: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function recordVendorContractSignatureAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const signedBy = String(formData.get("signedBy") ?? "").trim();
  if (!signedBy) {
    return { error: "A non-empty signatory name is required." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await recordVendorContractSignature(supabase, {
      contractId,
      expectedVersion,
      signedBy,
      signedAt: null,
      evidenceFileId: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not record the signature: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  return OK;
}

export async function activateVendorContractAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  _formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await activateVendorContract(supabase, { contractId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not activate: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function amendVendorContractAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to amend a vendor contract." };
  }
  const effectiveEnd = String(formData.get("effectiveEnd") ?? "").trim() || null;
  const paymentTermDaysRaw = String(formData.get("paymentTermDays") ?? "").trim();

  const supabase = await createSupabaseServerClient();
  let newContractId: string;
  try {
    const contract = await amendVendorContract(supabase, {
      contractId,
      expectedVersion,
      reason,
      effectiveEnd,
      rateVersionId: null,
      paymentTermDays: paymentTermDaysRaw.length > 0 ? Number(paymentTermDaysRaw) : null,
      slaTerms: null,
      capacityTerms: null,
      coverageTerms: null,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
    newContractId = contract.id;
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not amend: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, newContractId));
}

export async function renewVendorContractAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const newEffectiveStart = String(formData.get("newEffectiveStart") ?? "").trim();
  if (!newEffectiveStart) {
    return { error: "A new effective start date is required to renew." };
  }
  const newEffectiveEnd = String(formData.get("newEffectiveEnd") ?? "").trim() || null;

  const supabase = await createSupabaseServerClient();
  let newContractId: string;
  try {
    const contract = await renewVendorContract(supabase, { contractId, expectedVersion, newEffectiveStart, newEffectiveEnd, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    newContractId = contract.id;
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not renew: ${error.message}` };
    throw error;
  }

  revalidatePath(queuePath(tenantSlug));
  redirect(detailPath(tenantSlug, newContractId));
}

export async function suspendVendorContractAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to suspend a vendor contract." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await suspendVendorContract(supabase, { contractId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not suspend: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function reactivateVendorContractAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  _formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await reactivateVendorContract(supabase, { contractId, expectedVersion, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not reactivate: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function terminateVendorContractAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  const evidenceRef = String(formData.get("evidenceRef") ?? "").trim();
  if (!reason || !evidenceRef) {
    return { error: "A non-empty reason and evidence reference are both required to terminate a vendor contract." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await terminateVendorContract(supabase, { contractId, expectedVersion, reason, evidenceRef, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not terminate: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}

export async function cancelVendorContractDraftAction(
  tenantSlug: string,
  contractId: string,
  expectedVersion: number,
  _prevState: VendorContractActionState,
  formData: FormData,
): Promise<VendorContractActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const reason = String(formData.get("reason") ?? "").trim();
  if (!reason) {
    return { error: "A non-empty reason is required to cancel a vendor contract." };
  }

  const supabase = await createSupabaseServerClient();
  try {
    await cancelVendorContractDraft(supabase, { contractId, expectedVersion, reason, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorContractMutationError) return { error: `Could not cancel: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, contractId));
  revalidatePath(queuePath(tenantSlug));
  return OK;
}
