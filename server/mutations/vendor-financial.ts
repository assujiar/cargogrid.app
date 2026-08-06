/**
 * Vendor Banking and Tax Security mutation primitives (PRC-254, CG-S11-PRC-005).
 * Thin, typed wrappers around every bank-account-lifecycle/tax-identity-lifecycle/
 * payment-term-proposal RPC in
 * supabase/migrations/20260730610000_create_procurement_vendor_financial_security.sql,
 * including the two privileged, purpose-bound, MFA-gated reveal RPCs (deliberately
 * mutations, not reads -- a reveal is itself an audited event, see the contract
 * file's own header).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorBankAccountDraftInputSchema,
  UpdateVendorBankAccountDraftInputSchema,
  SubmitVendorBankAccountForApprovalInputSchema,
  DecideVendorBankAccountApprovalInputSchema,
  HoldVendorBankAccountInputSchema,
  ReactivateVendorBankAccountInputSchema,
  DeactivateVendorBankAccountInputSchema,
  RevealVendorBankAccountNumberInputSchema,
  AccessVendorBankAccountEvidenceInputSchema,
  CreateVendorTaxIdentityDraftInputSchema,
  UpdateVendorTaxIdentityDraftInputSchema,
  SubmitVendorTaxIdentityForApprovalInputSchema,
  DecideVendorTaxIdentityApprovalInputSchema,
  HoldVendorTaxIdentityInputSchema,
  ReactivateVendorTaxIdentityInputSchema,
  DeactivateVendorTaxIdentityInputSchema,
  RevealVendorTaxIdentityNumberInputSchema,
  AccessVendorTaxIdentityEvidenceInputSchema,
  ProposeVendorPaymentTermChangeInputSchema,
  DecideVendorPaymentTermChangeProposalInputSchema,
  parseVendorBankAccount,
  parseVendorBankAccountReveal,
  parseVendorTaxIdentity,
  parseVendorTaxIdentityReveal,
  parseVendorPaymentTermProposal,
  parseVendorFinancialEvidenceAccess,
  type CreateVendorBankAccountDraftInput,
  type UpdateVendorBankAccountDraftInput,
  type SubmitVendorBankAccountForApprovalInput,
  type DecideVendorBankAccountApprovalInput,
  type HoldVendorBankAccountInput,
  type ReactivateVendorBankAccountInput,
  type DeactivateVendorBankAccountInput,
  type RevealVendorBankAccountNumberInput,
  type AccessVendorBankAccountEvidenceInput,
  type CreateVendorTaxIdentityDraftInput,
  type UpdateVendorTaxIdentityDraftInput,
  type SubmitVendorTaxIdentityForApprovalInput,
  type DecideVendorTaxIdentityApprovalInput,
  type HoldVendorTaxIdentityInput,
  type ReactivateVendorTaxIdentityInput,
  type DeactivateVendorTaxIdentityInput,
  type RevealVendorTaxIdentityNumberInput,
  type AccessVendorTaxIdentityEvidenceInput,
  type ProposeVendorPaymentTermChangeInput,
  type DecideVendorPaymentTermChangeProposalInput,
  type VendorBankAccount,
  type VendorBankAccountReveal,
  type VendorTaxIdentity,
  type VendorTaxIdentityReveal,
  type VendorPaymentTermProposal,
  type VendorFinancialEvidenceAccess,
} from "../contracts/vendor-financial/vendor-financial.ts";

export type VendorFinancialMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_FINANCIAL_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "vendor_profile_not_found",
  "invalid_account_holder_name",
  "invalid_bank_name",
  "invalid_account_number",
  "invalid_currency",
  "invalid_purpose",
  "financial_evidence_file_mismatch",
  "financial_unsafe_evidence",
  "evidence_file_not_found",
  "idempotency_key_conflict",
  "vendor_bank_account_not_found",
  "vendor_bank_account_not_draft",
  "stale_version",
  "invalid_transition",
  "reauth_required",
  "self_approval_not_allowed",
  "self_reactivation_not_allowed",
  "invalid_decision",
  "reason_required",
  "superseded_account_not_found",
  "invalid_supersede",
  "active_account_exists",
  "reveal_reason_required",
  "encryption_key_not_configured",
  "invalid_access_type",
  "no_evidence_attached",
  "invalid_tax_id_type",
  "invalid_legal_name",
  "invalid_tax_id",
  "vendor_tax_identity_not_found",
  "vendor_tax_identity_not_draft",
  "superseded_tax_identity_not_found",
  "active_tax_identity_exists",
  "invalid_payment_term_days",
  "no_op_proposal",
  "pending_proposal_exists",
  "vendor_payment_term_proposal_not_found",
  "vendor_profile_changed_since_proposal",
  "invalid_status_filter",
  "invalid_response",
] as const;
type KnownVendorFinancialMutationErrorCode = (typeof VENDOR_FINANCIAL_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorFinancialMutationErrorCode = KnownVendorFinancialMutationErrorCode | "mutation_failed";

export class VendorFinancialMutationError extends Error {
  readonly code: VendorFinancialMutationErrorCode;

  constructor(code: VendorFinancialMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorFinancialMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorFinancialMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_FINANCIAL_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorFinancialMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseBankAccountResponse(data: unknown, rpcName: string): VendorBankAccount {
  const row = firstRow(data);
  if (!row) throw new VendorFinancialMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorBankAccount(row);
}

function parseTaxIdentityResponse(data: unknown, rpcName: string): VendorTaxIdentity {
  const row = firstRow(data);
  if (!row) throw new VendorFinancialMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorTaxIdentity(row);
}

function parsePaymentTermProposalResponse(data: unknown, rpcName: string): VendorPaymentTermProposal {
  const row = firstRow(data);
  if (!row) throw new VendorFinancialMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorPaymentTermProposal(row);
}

// --- Bank account lifecycle ---

export async function createVendorBankAccountDraft(client: VendorFinancialMutationRpcClient, input: CreateVendorBankAccountDraftInput): Promise<VendorBankAccount> {
  const parsed = CreateVendorBankAccountDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_bank_account_draft", {
    p_vendor_master_record_id: parsed.vendorMasterRecordId,
    p_account_holder_name: parsed.accountHolderName,
    p_bank_name: parsed.bankName,
    p_account_number: parsed.bankAccountNumber,
    p_currency: parsed.currency,
    p_purpose: parsed.purpose ?? null,
    p_effective_from: parsed.effectiveFrom ?? null,
    p_evidence_file_id: parsed.evidenceFileId ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseBankAccountResponse(data, "create_vendor_bank_account_draft");
}

export async function updateVendorBankAccountDraft(client: VendorFinancialMutationRpcClient, input: UpdateVendorBankAccountDraftInput): Promise<VendorBankAccount> {
  const parsed = UpdateVendorBankAccountDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_bank_account_draft", {
    p_account_id: parsed.accountId,
    p_expected_version: parsed.expectedVersion,
    p_account_holder_name: parsed.accountHolderName,
    p_bank_name: parsed.bankName,
    p_account_number: parsed.bankAccountNumber,
    p_currency: parsed.currency,
    p_purpose: parsed.purpose ?? null,
    p_effective_from: parsed.effectiveFrom ?? null,
    p_evidence_file_id: parsed.evidenceFileId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseBankAccountResponse(data, "update_vendor_bank_account_draft");
}

export async function submitVendorBankAccountForApproval(client: VendorFinancialMutationRpcClient, input: SubmitVendorBankAccountForApprovalInput): Promise<VendorBankAccount> {
  const parsed = SubmitVendorBankAccountForApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_vendor_bank_account_for_approval", {
    p_account_id: parsed.accountId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseBankAccountResponse(data, "submit_vendor_bank_account_for_approval");
}

/** The privileged checker decision. Mandatory maker-checker (self_approval_not_allowed) and MFA reauth freshness (<=5 minutes, server-enforced) -- reauthConfirmedAt must be a timestamp the caller's own client-side re-authentication step just produced. */
export async function decideVendorBankAccountApproval(client: VendorFinancialMutationRpcClient, input: DecideVendorBankAccountApprovalInput): Promise<VendorBankAccount> {
  const parsed = DecideVendorBankAccountApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_bank_account_approval", {
    p_account_id: parsed.accountId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_supersedes_account_id: parsed.supersedesAccountId ?? null,
    p_rejection_reason: parsed.rejectionReason ?? null,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseBankAccountResponse(data, "decide_vendor_bank_account_approval");
}

export async function holdVendorBankAccount(client: VendorFinancialMutationRpcClient, input: HoldVendorBankAccountInput): Promise<VendorBankAccount> {
  const parsed = HoldVendorBankAccountInputSchema.parse(input);
  const { data, error } = await client.rpc("hold_vendor_bank_account", {
    p_account_id: parsed.accountId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseBankAccountResponse(data, "hold_vendor_bank_account");
}

/** reauthConfirmedAt must be fresh; the RPC also rejects reactivation by the same identity that placed the hold (self_reactivation_not_allowed). */
export async function reactivateVendorBankAccount(client: VendorFinancialMutationRpcClient, input: ReactivateVendorBankAccountInput): Promise<VendorBankAccount> {
  const parsed = ReactivateVendorBankAccountInputSchema.parse(input);
  const { data, error } = await client.rpc("reactivate_vendor_bank_account", {
    p_account_id: parsed.accountId,
    p_expected_version: parsed.expectedVersion,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseBankAccountResponse(data, "reactivate_vendor_bank_account");
}

export async function deactivateVendorBankAccount(client: VendorFinancialMutationRpcClient, input: DeactivateVendorBankAccountInput): Promise<VendorBankAccount> {
  const parsed = DeactivateVendorBankAccountInputSchema.parse(input);
  const { data, error } = await client.rpc("deactivate_vendor_bank_account", {
    p_account_id: parsed.accountId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseBankAccountResponse(data, "deactivate_vendor_bank_account");
}

/**
 * The ONLY call path that ever decrypts a bank account number. Purpose-bound
 * (revealReason mandatory) and MFA-gated (reauthConfirmedAt must be fresh). Every
 * successful call is unconditionally audited server-side (app.audit_logs) -- this is
 * a deliberate, explicit user action (a "Reveal" button), never a passive page-load
 * read; the UI layer must never call this from a useEffect/render path.
 */
export async function revealVendorBankAccountNumber(client: VendorFinancialMutationRpcClient, input: RevealVendorBankAccountNumberInput): Promise<VendorBankAccountReveal> {
  const parsed = RevealVendorBankAccountNumberInputSchema.parse(input);
  const { data, error } = await client.rpc("reveal_vendor_bank_account_number", {
    p_account_id: parsed.accountId,
    p_reveal_reason: parsed.revealReason,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_correlation_id: parsed.correlationId ?? null,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialMutationError("invalid_response", "reveal_vendor_bank_account_number returned no row");
  return parseVendorBankAccountReveal(row);
}

export async function accessVendorBankAccountEvidence(client: VendorFinancialMutationRpcClient, input: AccessVendorBankAccountEvidenceInput): Promise<VendorFinancialEvidenceAccess> {
  const parsed = AccessVendorBankAccountEvidenceInputSchema.parse(input);
  const { data, error } = await client.rpc("access_vendor_bank_account_evidence", {
    p_account_id: parsed.accountId,
    p_access_type: parsed.accessType,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_correlation_id: parsed.correlationId ?? null,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialMutationError("invalid_response", "access_vendor_bank_account_evidence returned no row");
  return parseVendorFinancialEvidenceAccess(row);
}

// --- Tax identity lifecycle (mirrors bank account exactly) ---

export async function createVendorTaxIdentityDraft(client: VendorFinancialMutationRpcClient, input: CreateVendorTaxIdentityDraftInput): Promise<VendorTaxIdentity> {
  const parsed = CreateVendorTaxIdentityDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_tax_identity_draft", {
    p_vendor_master_record_id: parsed.vendorMasterRecordId,
    p_tax_id_type: parsed.taxIdType,
    p_tax_id: parsed.taxIdNumber,
    p_legal_name_on_file: parsed.legalNameOnFile,
    p_effective_from: parsed.effectiveFrom ?? null,
    p_evidence_file_id: parsed.evidenceFileId ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseTaxIdentityResponse(data, "create_vendor_tax_identity_draft");
}

export async function updateVendorTaxIdentityDraft(client: VendorFinancialMutationRpcClient, input: UpdateVendorTaxIdentityDraftInput): Promise<VendorTaxIdentity> {
  const parsed = UpdateVendorTaxIdentityDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_tax_identity_draft", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_expected_version: parsed.expectedVersion,
    p_tax_id_type: parsed.taxIdType,
    p_tax_id: parsed.taxIdNumber,
    p_legal_name_on_file: parsed.legalNameOnFile,
    p_effective_from: parsed.effectiveFrom ?? null,
    p_evidence_file_id: parsed.evidenceFileId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseTaxIdentityResponse(data, "update_vendor_tax_identity_draft");
}

export async function submitVendorTaxIdentityForApproval(client: VendorFinancialMutationRpcClient, input: SubmitVendorTaxIdentityForApprovalInput): Promise<VendorTaxIdentity> {
  const parsed = SubmitVendorTaxIdentityForApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_vendor_tax_identity_for_approval", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseTaxIdentityResponse(data, "submit_vendor_tax_identity_for_approval");
}

export async function decideVendorTaxIdentityApproval(client: VendorFinancialMutationRpcClient, input: DecideVendorTaxIdentityApprovalInput): Promise<VendorTaxIdentity> {
  const parsed = DecideVendorTaxIdentityApprovalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_tax_identity_approval", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_supersedes_tax_identity_id: parsed.supersedesTaxIdentityId ?? null,
    p_rejection_reason: parsed.rejectionReason ?? null,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseTaxIdentityResponse(data, "decide_vendor_tax_identity_approval");
}

export async function holdVendorTaxIdentity(client: VendorFinancialMutationRpcClient, input: HoldVendorTaxIdentityInput): Promise<VendorTaxIdentity> {
  const parsed = HoldVendorTaxIdentityInputSchema.parse(input);
  const { data, error } = await client.rpc("hold_vendor_tax_identity", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseTaxIdentityResponse(data, "hold_vendor_tax_identity");
}

/** reauthConfirmedAt must be fresh; the RPC also rejects reactivation by the same identity that placed the hold (self_reactivation_not_allowed). */
export async function reactivateVendorTaxIdentity(client: VendorFinancialMutationRpcClient, input: ReactivateVendorTaxIdentityInput): Promise<VendorTaxIdentity> {
  const parsed = ReactivateVendorTaxIdentityInputSchema.parse(input);
  const { data, error } = await client.rpc("reactivate_vendor_tax_identity", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_expected_version: parsed.expectedVersion,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseTaxIdentityResponse(data, "reactivate_vendor_tax_identity");
}

export async function deactivateVendorTaxIdentity(client: VendorFinancialMutationRpcClient, input: DeactivateVendorTaxIdentityInput): Promise<VendorTaxIdentity> {
  const parsed = DeactivateVendorTaxIdentityInputSchema.parse(input);
  const { data, error } = await client.rpc("deactivate_vendor_tax_identity", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parseTaxIdentityResponse(data, "deactivate_vendor_tax_identity");
}

/** The ONLY call path that ever decrypts a tax identifier. See revealVendorBankAccountNumber's own doc comment -- identical purpose-bound/MFA-gated/unconditionally-audited/deliberate-user-action discipline. */
export async function revealVendorTaxIdentityNumber(client: VendorFinancialMutationRpcClient, input: RevealVendorTaxIdentityNumberInput): Promise<VendorTaxIdentityReveal> {
  const parsed = RevealVendorTaxIdentityNumberInputSchema.parse(input);
  const { data, error } = await client.rpc("reveal_vendor_tax_identity_number", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_reveal_reason: parsed.revealReason,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_correlation_id: parsed.correlationId ?? null,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialMutationError("invalid_response", "reveal_vendor_tax_identity_number returned no row");
  return parseVendorTaxIdentityReveal(row);
}

export async function accessVendorTaxIdentityEvidence(client: VendorFinancialMutationRpcClient, input: AccessVendorTaxIdentityEvidenceInput): Promise<VendorFinancialEvidenceAccess> {
  const parsed = AccessVendorTaxIdentityEvidenceInputSchema.parse(input);
  const { data, error } = await client.rpc("access_vendor_tax_identity_evidence", {
    p_tax_identity_id: parsed.taxIdentityId,
    p_access_type: parsed.accessType,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_correlation_id: parsed.correlationId ?? null,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorFinancialMutationError("invalid_response", "access_vendor_tax_identity_evidence returned no row");
  return parseVendorFinancialEvidenceAccess(row);
}

// --- Payment-term change proposal/approval (design note 10) ---

export async function proposeVendorPaymentTermChange(client: VendorFinancialMutationRpcClient, input: ProposeVendorPaymentTermChangeInput): Promise<VendorPaymentTermProposal> {
  const parsed = ProposeVendorPaymentTermChangeInputSchema.parse(input);
  const { data, error } = await client.rpc("propose_vendor_payment_term_change", {
    p_vendor_master_record_id: parsed.vendorMasterRecordId,
    p_proposed_payment_term_days: parsed.proposedPaymentTermDays,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parsePaymentTermProposalResponse(data, "propose_vendor_payment_term_change");
}

/** Approving updates app.vendor_profiles.payment_term_days directly, guarded by the vendor profile's own record_version snapshotted at proposal time (design note 10) -- an unrelated concurrent profile change surfaces vendor_profile_changed_since_proposal rather than silently overwriting it. */
export async function decideVendorPaymentTermChangeProposal(client: VendorFinancialMutationRpcClient, input: DecideVendorPaymentTermChangeProposalInput): Promise<VendorPaymentTermProposal> {
  const parsed = DecideVendorPaymentTermChangeProposalInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_payment_term_change_proposal", {
    p_proposal_id: parsed.proposalId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decision_reason: parsed.decisionReason ?? null,
    p_reauth_confirmed_at: parsed.reauthConfirmedAt,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorFinancialMutationError(classifyError(error.message), error.message);
  return parsePaymentTermProposalResponse(data, "decide_vendor_payment_term_change_proposal");
}
