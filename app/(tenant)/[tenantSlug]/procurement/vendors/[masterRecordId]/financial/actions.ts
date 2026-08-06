"use server";

/**
 * Vendor Banking and Tax Security Server Actions (PRC-254, CG-S11-PRC-005). Mirrors
 * app/(tenant)/[tenantSlug]/procurement/compliance/vendors/actions.ts's own
 * runAction/requireAccess shape. The decide/reveal actions additionally take a
 * `reauthConfirmedAt` ISO timestamp captured client-side at submit time -- the exact,
 * already-established `credit-approval-decision-form.tsx` (COM-157) attestation
 * pattern this repository already uses for every other privileged-approver action;
 * no live MFA challenge UI exists anywhere in this repository (a disclosed boundary
 * this capability's own migration header names explicitly), and the server
 * independently re-validates freshness (<=5 minutes) on every call regardless.
 */

import { revalidatePath } from "next/cache";
import { createSupabaseServerClient } from "../../../../../../../lib/supabase/server.ts";
import { createSupabaseServiceRoleClient } from "../../../../../../../lib/supabase/service-role.ts";
import { resolveProcurementAccessForRequest } from "../../../../../../../lib/portal/resolve-procurement-access.server.ts";
import {
  createVendorBankAccountDraft,
  updateVendorBankAccountDraft,
  submitVendorBankAccountForApproval,
  decideVendorBankAccountApproval,
  holdVendorBankAccount,
  reactivateVendorBankAccount,
  deactivateVendorBankAccount,
  revealVendorBankAccountNumber,
  accessVendorBankAccountEvidence,
  createVendorTaxIdentityDraft,
  updateVendorTaxIdentityDraft,
  submitVendorTaxIdentityForApproval,
  decideVendorTaxIdentityApproval,
  holdVendorTaxIdentity,
  reactivateVendorTaxIdentity,
  deactivateVendorTaxIdentity,
  revealVendorTaxIdentityNumber,
  accessVendorTaxIdentityEvidence,
  proposeVendorPaymentTermChange,
  decideVendorPaymentTermChangeProposal,
  VendorFinancialMutationError,
} from "../../../../../../../server/mutations/vendor-financial.ts";
import { initiateFileUpload, DocumentMutationError, type DocumentMutationRpcClient } from "../../../../../../../server/mutations/document.ts";
import type { VendorFinancialDecision, VendorFinancialAccessType, VendorFinancialEvidenceAccess, VendorBankAccountReveal, VendorTaxIdentityReveal } from "../../../../../../../server/contracts/vendor-financial/vendor-financial.ts";

export interface VendorFinancialActionState {
  readonly error: string | null;
}

const OK: VendorFinancialActionState = { error: null };
const NO_ACCESS: VendorFinancialActionState = { error: "You don't have access to this organization's Procurement workspace." };

async function requireAccess(tenantSlug: string) {
  const access = await resolveProcurementAccessForRequest(tenantSlug);
  if (access.status !== "allowed") return null;
  return access;
}

/** Same adapter shape as procurement/compliance/vendors/actions.ts's own toDocumentClient -- app.initiate_file_upload is service_role-only (PLT-128). */
function toDocumentClient(client: ReturnType<typeof createSupabaseServiceRoleClient>): DocumentMutationRpcClient {
  return client as unknown as DocumentMutationRpcClient;
}

function detailPath(tenantSlug: string, vendorMasterRecordId: string): string {
  return `/${tenantSlug}/procurement/vendors/${vendorMasterRecordId}/financial`;
}

type Mutation = (client: Awaited<ReturnType<typeof createSupabaseServerClient>>, input: never) => Promise<unknown>;

async function runAction(tenantSlug: string, vendorMasterRecordId: string, mutation: Mutation, input: Record<string, unknown>, failureVerb: string): Promise<VendorFinancialActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const supabase = await createSupabaseServerClient();
  try {
    await mutation(supabase, { ...input, actorAuthUserId: access.authUserId, actorLabel: access.authUserId } as never);
  } catch (error) {
    if (error instanceof VendorFinancialMutationError) return { error: `Could not ${failureVerb}: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterRecordId));
  return OK;
}

async function uploadEvidence(tenantId: string, vendorMasterRecordId: string, actorAuthUserId: string, file: File): Promise<string> {
  const uploaded = await initiateFileUpload(toDocumentClient(createSupabaseServiceRoleClient()), {
    tenantId,
    documentTypeCode: "vendor_financial_verification_document",
    recordType: "vendor_financial_verification",
    recordId: vendorMasterRecordId,
    originalFilename: file.name,
    mimeType: file.type || "application/octet-stream",
    sizeBytes: file.size,
    classification: "confidential",
    legalHold: false,
    legalHoldReason: null,
    sharedOrgUnitIds: undefined,
    customerAccountRef: null,
    idempotencyKey: null,
    actorAuthUserId,
    actorLabel: actorAuthUserId,
  });
  return uploaded.id;
}

// --- Bank account lifecycle ---

export async function createVendorBankAccountDraftAction(tenantSlug: string, vendorMasterRecordId: string, _prevState: VendorFinancialActionState, formData: FormData): Promise<VendorFinancialActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const accountHolderName = String(formData.get("accountHolderName") ?? "").trim();
  const bankName = String(formData.get("bankName") ?? "").trim();
  const bankAccountNumber = String(formData.get("bankAccountNumber") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const purpose = (String(formData.get("purpose") ?? "primary").trim() || "primary") as "primary" | "settlement" | "other";
  const evidenceFile = formData.get("evidenceFile");

  const supabase = await createSupabaseServerClient();

  let evidenceFileId: string | null = null;
  if (evidenceFile instanceof File && evidenceFile.size > 0) {
    try {
      evidenceFileId = await uploadEvidence(access.tenant.id, vendorMasterRecordId, access.authUserId, evidenceFile);
    } catch (error) {
      if (error instanceof DocumentMutationError) return { error: `Could not upload this evidence file: ${error.message}` };
      throw error;
    }
  }

  try {
    await createVendorBankAccountDraft(supabase, {
      vendorMasterRecordId,
      accountHolderName,
      bankName,
      bankAccountNumber,
      currency,
      purpose,
      evidenceFileId,
      actorAuthUserId: access.authUserId,
      actorLabel: access.authUserId,
    });
  } catch (error) {
    if (error instanceof VendorFinancialMutationError) return { error: `Could not propose this bank account: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterRecordId));
  return OK;
}

export async function updateVendorBankAccountDraftAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  accountId: string,
  expectedVersion: number,
  _prevState: VendorFinancialActionState,
  formData: FormData,
) {
  const accountHolderName = String(formData.get("accountHolderName") ?? "").trim();
  const bankName = String(formData.get("bankName") ?? "").trim();
  const bankAccountNumber = String(formData.get("bankAccountNumber") ?? "").trim();
  const currency = String(formData.get("currency") ?? "").trim().toUpperCase();
  const purpose = (String(formData.get("purpose") ?? "primary").trim() || "primary") as "primary" | "settlement" | "other";
  return runAction(tenantSlug, vendorMasterRecordId, updateVendorBankAccountDraft as Mutation, { accountId, expectedVersion, accountHolderName, bankName, bankAccountNumber, currency, purpose }, "update this bank account draft");
}

export async function submitVendorBankAccountForApprovalAction(tenantSlug: string, vendorMasterRecordId: string, accountId: string, expectedVersion: number, _prevState: VendorFinancialActionState, _formData: FormData) {
  return runAction(tenantSlug, vendorMasterRecordId, submitVendorBankAccountForApproval as Mutation, { accountId, expectedVersion }, "submit this bank account for approval");
}

/** The maker-checker decision. reauthConfirmedAt is the caller's own client-captured attestation timestamp (see this file's own header). */
export async function decideVendorBankAccountApprovalAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  accountId: string,
  expectedVersion: number,
  decision: VendorFinancialDecision,
  rejectionReason: string | null,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, decideVendorBankAccountApproval as Mutation, { accountId, expectedVersion, decision, rejectionReason, reauthConfirmedAt }, "record this decision");
}

/**
 * hold/reactivate/deactivate now require the same MFA reauth freshness proof as
 * decide/reveal (spec-compliance fix -- these RPCs mutate the record's own
 * effective, downstream-consumed verification status, exactly what Sec.24's
 * "no bank change becomes effective without ... privileged current authentication"
 * protects). Plain async calls (not the useActionState/FormData shape) so the UI can
 * capture reauthConfirmedAt client-side at click time, mirroring decideBankAccountAction.
 */
export async function holdVendorBankAccountAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  accountId: string,
  expectedVersion: number,
  reason: string,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, holdVendorBankAccount as Mutation, { accountId, expectedVersion, reason, reauthConfirmedAt }, "place this account on hold");
}

/** The RPC also rejects reactivation by the same identity that placed the hold (self_reactivation_not_allowed). */
export async function reactivateVendorBankAccountAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  accountId: string,
  expectedVersion: number,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, reactivateVendorBankAccount as Mutation, { accountId, expectedVersion, reauthConfirmedAt }, "reactivate this account");
}

export async function deactivateVendorBankAccountAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  accountId: string,
  expectedVersion: number,
  reason: string,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, deactivateVendorBankAccount as Mutation, { accountId, expectedVersion, reason, reauthConfirmedAt }, "deactivate this account");
}

export interface VendorBankAccountRevealActionState {
  readonly error: string | null;
  readonly reveal: VendorBankAccountReveal | null;
}

/**
 * The reveal action -- deliberately requires an explicit call (a "Reveal" button
 * click), NEVER fired on page load. revealReason is purpose-bound (Sec.16);
 * reauthConfirmedAt is the same client-captured attestation as the decide action.
 */
export async function revealVendorBankAccountNumberAction(
  tenantSlug: string,
  accountId: string,
  revealReason: string,
  reauthConfirmedAt: string,
): Promise<VendorBankAccountRevealActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, reveal: null };

  const supabase = await createSupabaseServerClient();
  try {
    const reveal = await revealVendorBankAccountNumber(supabase, { accountId, revealReason, reauthConfirmedAt, correlationId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    return { error: null, reveal };
  } catch (error) {
    if (error instanceof VendorFinancialMutationError) return { error: `Could not reveal this account number: ${error.message}`, reveal: null };
    throw error;
  }
}

export interface VendorFinancialEvidenceAccessState {
  readonly error: string | null;
  readonly access: VendorFinancialEvidenceAccess | null;
}

export async function accessVendorBankAccountEvidenceAction(tenantSlug: string, accountId: string, accessType: VendorFinancialAccessType): Promise<VendorFinancialEvidenceAccessState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, access: null };

  const supabase = await createSupabaseServerClient();
  try {
    const result = await accessVendorBankAccountEvidence(supabase, { accountId, accessType, correlationId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    return { error: null, access: result };
  } catch (error) {
    if (error instanceof VendorFinancialMutationError) return { error: `Could not access this evidence file: ${error.message}`, access: null };
    throw error;
  }
}

// --- Tax identity lifecycle (mirrors bank account exactly) ---

export async function createVendorTaxIdentityDraftAction(tenantSlug: string, vendorMasterRecordId: string, _prevState: VendorFinancialActionState, formData: FormData): Promise<VendorFinancialActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return NO_ACCESS;

  const taxIdType = String(formData.get("taxIdType") ?? "").trim();
  const taxIdNumber = String(formData.get("taxIdNumber") ?? "").trim();
  const legalNameOnFile = String(formData.get("legalNameOnFile") ?? "").trim();
  const evidenceFile = formData.get("evidenceFile");

  const supabase = await createSupabaseServerClient();

  let evidenceFileId: string | null = null;
  if (evidenceFile instanceof File && evidenceFile.size > 0) {
    try {
      evidenceFileId = await uploadEvidence(access.tenant.id, vendorMasterRecordId, access.authUserId, evidenceFile);
    } catch (error) {
      if (error instanceof DocumentMutationError) return { error: `Could not upload this evidence file: ${error.message}` };
      throw error;
    }
  }

  try {
    await createVendorTaxIdentityDraft(supabase, { vendorMasterRecordId, taxIdType, taxIdNumber, legalNameOnFile, evidenceFileId, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
  } catch (error) {
    if (error instanceof VendorFinancialMutationError) return { error: `Could not propose this tax identity: ${error.message}` };
    throw error;
  }

  revalidatePath(detailPath(tenantSlug, vendorMasterRecordId));
  return OK;
}

export async function updateVendorTaxIdentityDraftAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  taxIdentityId: string,
  expectedVersion: number,
  _prevState: VendorFinancialActionState,
  formData: FormData,
) {
  const taxIdType = String(formData.get("taxIdType") ?? "").trim();
  const taxIdNumber = String(formData.get("taxIdNumber") ?? "").trim();
  const legalNameOnFile = String(formData.get("legalNameOnFile") ?? "").trim();
  return runAction(tenantSlug, vendorMasterRecordId, updateVendorTaxIdentityDraft as Mutation, { taxIdentityId, expectedVersion, taxIdType, taxIdNumber, legalNameOnFile }, "update this tax identity draft");
}

export async function submitVendorTaxIdentityForApprovalAction(tenantSlug: string, vendorMasterRecordId: string, taxIdentityId: string, expectedVersion: number, _prevState: VendorFinancialActionState, _formData: FormData) {
  return runAction(tenantSlug, vendorMasterRecordId, submitVendorTaxIdentityForApproval as Mutation, { taxIdentityId, expectedVersion }, "submit this tax identity for approval");
}

export async function decideVendorTaxIdentityApprovalAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  taxIdentityId: string,
  expectedVersion: number,
  decision: VendorFinancialDecision,
  rejectionReason: string | null,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, decideVendorTaxIdentityApproval as Mutation, { taxIdentityId, expectedVersion, decision, rejectionReason, reauthConfirmedAt }, "record this decision");
}

export async function holdVendorTaxIdentityAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  taxIdentityId: string,
  expectedVersion: number,
  reason: string,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, holdVendorTaxIdentity as Mutation, { taxIdentityId, expectedVersion, reason, reauthConfirmedAt }, "place this tax identity on hold");
}

/** The RPC also rejects reactivation by the same identity that placed the hold (self_reactivation_not_allowed). */
export async function reactivateVendorTaxIdentityAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  taxIdentityId: string,
  expectedVersion: number,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, reactivateVendorTaxIdentity as Mutation, { taxIdentityId, expectedVersion, reauthConfirmedAt }, "reactivate this tax identity");
}

export async function deactivateVendorTaxIdentityAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  taxIdentityId: string,
  expectedVersion: number,
  reason: string,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, deactivateVendorTaxIdentity as Mutation, { taxIdentityId, expectedVersion, reason, reauthConfirmedAt }, "deactivate this tax identity");
}

export interface VendorTaxIdentityRevealActionState {
  readonly error: string | null;
  readonly reveal: VendorTaxIdentityReveal | null;
}

export async function revealVendorTaxIdentityNumberAction(tenantSlug: string, taxIdentityId: string, revealReason: string, reauthConfirmedAt: string): Promise<VendorTaxIdentityRevealActionState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, reveal: null };

  const supabase = await createSupabaseServerClient();
  try {
    const reveal = await revealVendorTaxIdentityNumber(supabase, { taxIdentityId, revealReason, reauthConfirmedAt, correlationId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    return { error: null, reveal };
  } catch (error) {
    if (error instanceof VendorFinancialMutationError) return { error: `Could not reveal this tax identifier: ${error.message}`, reveal: null };
    throw error;
  }
}

export async function accessVendorTaxIdentityEvidenceAction(tenantSlug: string, taxIdentityId: string, accessType: VendorFinancialAccessType): Promise<VendorFinancialEvidenceAccessState> {
  const access = await requireAccess(tenantSlug);
  if (!access) return { error: NO_ACCESS.error, access: null };

  const supabase = await createSupabaseServerClient();
  try {
    const result = await accessVendorTaxIdentityEvidence(supabase, { taxIdentityId, accessType, correlationId: null, actorAuthUserId: access.authUserId, actorLabel: access.authUserId });
    return { error: null, access: result };
  } catch (error) {
    if (error instanceof VendorFinancialMutationError) return { error: `Could not access this evidence file: ${error.message}`, access: null };
    throw error;
  }
}

// --- Payment-term change proposal/approval ---

export async function proposeVendorPaymentTermChangeAction(tenantSlug: string, vendorMasterRecordId: string, _prevState: VendorFinancialActionState, formData: FormData) {
  const proposedPaymentTermDays = Number(formData.get("proposedPaymentTermDays") ?? "");
  const reason = String(formData.get("reason") ?? "").trim();
  return runAction(tenantSlug, vendorMasterRecordId, proposeVendorPaymentTermChange as Mutation, { vendorMasterRecordId, proposedPaymentTermDays, reason }, "propose this payment-term change");
}

export async function decideVendorPaymentTermChangeProposalAction(
  tenantSlug: string,
  vendorMasterRecordId: string,
  proposalId: string,
  expectedVersion: number,
  decision: VendorFinancialDecision,
  decisionReason: string | null,
  reauthConfirmedAt: string,
): Promise<VendorFinancialActionState> {
  return runAction(tenantSlug, vendorMasterRecordId, decideVendorPaymentTermChangeProposal as Mutation, { proposalId, expectedVersion, decision, decisionReason, reauthConfirmedAt }, "record this decision");
}
