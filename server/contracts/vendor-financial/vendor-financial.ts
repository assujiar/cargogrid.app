/**
 * Vendor Banking and Tax Security contract (PRC-254, CG-S11-PRC-005). Mirrors
 * supabase/migrations/20260730610000_create_procurement_vendor_financial_security.sql's
 * app.vendor_bank_accounts/app.vendor_tax_identities/app.vendor_payment_term_proposals
 * shapes and their RPCs. Follows the exact directory convention PRC-251/252/253
 * established: Zod schemas here, list/read projections in
 * server/queries/vendor-financial.ts, RPC-calling mutation wrappers with an
 * enumerated error-code type in server/mutations/vendor-financial.ts.
 *
 * This repository's FIRST at-rest confidentiality mechanism -- see the migration's
 * own header for the full encryption design (pgcrypto pgp_sym_encrypt, a fail-closed
 * `app.vendor_financial_encryption_key()` GUC read, a deterministic sha256 hash for
 * duplicate detection without decryption, and a plain last-4 masked-display value).
 * The masked schemas below (VendorBankAccountSchema/VendorTaxIdentitySchema) NEVER
 * carry the encrypted or decrypted value -- only `*Last4`. The two reveal schemas
 * (VendorBankAccountRevealSchema/VendorTaxIdentityRevealSchema) are the ONLY shapes
 * in this file that ever carry a real plaintext secret, and exist solely as the
 * return type of the two privileged, audited, MFA-gated reveal RPCs
 * (app.reveal_vendor_bank_account_number/app.reveal_vendor_tax_identity_number).
 *
 * Field naming note (ISS-2026-008 / scripts/observability/logger.ts's own
 * SENSITIVE_KEY_PATTERN, `/secret|password|token|key|authorization|cookie|ssn|npwp|
 * bank|account_number|salary|payroll/i`, mirrored verbatim by
 * app.redact_audit_payload at the database layer, PLT-116): the reveal schema's own
 * plaintext bank-account field is named `bankAccountNumber` (verified: matches the
 * pattern via "bank", so a future accidental `logger.log()` of a reveal response
 * would still redact it) rather than a bare `accountNumber` (verified NOT to match
 * -- `accountNumber` alone contains neither "bank" nor the literal "account_number"
 * substring). The tax-identity reveal field (`taxIdNumber`) is a disclosed, narrower
 * gap: the shared pattern only covers the literal "npwp", not a generic tax
 * identifier (this capability's own `tax_id_type` is deliberately free text per
 * RPD-016 -- no NPWP-specific handling is hardcoded), so a generic tax id field name
 * cannot be made to match without widening that shared, repository-wide regex, which
 * is out of this capability's own file scope. Neither `server/queries/vendor-
 * financial.ts` nor `server/mutations/vendor-financial.ts` ever calls the structured
 * logger with a raw reveal response regardless -- this is a defense-in-depth note,
 * not a live logging call site.
 */

import { z } from "zod";

export const VENDOR_FINANCIAL_LIFECYCLE_STATUSES = ["draft", "pending_approval", "active", "rejected", "hold", "deactivated"] as const;
export const VendorFinancialLifecycleStatusSchema = z.enum(VENDOR_FINANCIAL_LIFECYCLE_STATUSES);
export type VendorFinancialLifecycleStatus = z.infer<typeof VendorFinancialLifecycleStatusSchema>;

export const VENDOR_BANK_ACCOUNT_PURPOSES = ["primary", "settlement", "other"] as const;
export const VendorBankAccountPurposeSchema = z.enum(VENDOR_BANK_ACCOUNT_PURPOSES);
export type VendorBankAccountPurpose = z.infer<typeof VendorBankAccountPurposeSchema>;

export const VENDOR_FINANCIAL_DECISIONS = ["approved", "rejected"] as const;
export const VendorFinancialDecisionSchema = z.enum(VENDOR_FINANCIAL_DECISIONS);
export type VendorFinancialDecision = z.infer<typeof VendorFinancialDecisionSchema>;

export const VENDOR_FINANCIAL_ACCESS_TYPES = ["signed_url_issued", "download", "metadata_view"] as const;
export const VendorFinancialAccessTypeSchema = z.enum(VENDOR_FINANCIAL_ACCESS_TYPES);
export type VendorFinancialAccessType = z.infer<typeof VendorFinancialAccessTypeSchema>;

export const VENDOR_FINANCIAL_ACCESS_RESULTS = ["granted", "denied"] as const;
export const VendorFinancialAccessResultSchema = z.enum(VENDOR_FINANCIAL_ACCESS_RESULTS);
export type VendorFinancialAccessResult = z.infer<typeof VendorFinancialAccessResultSchema>;

// --- Core rows (masked -- NEVER carry the encrypted or decrypted value) ---

/** app.get_vendor_bank_account_masked / app.list_vendor_bank_accounts_masked's own row shape. isDuplicateCandidate is a live, hash-based, decryption-free fraud signal (design note 2). */
export const VendorBankAccountSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  accountFamilyId: z.string().uuid(),
  accountHolderName: z.string(),
  bankName: z.string(),
  accountNumberLast4: z.string(),
  currency: z.string(),
  purpose: VendorBankAccountPurposeSchema,
  status: VendorFinancialLifecycleStatusSchema,
  effectiveFrom: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  isDuplicateCandidate: z.boolean(),
  proposedBy: z.string().nullable(),
  approvedBy: z.string().nullable(),
  holdReason: z.string().nullable(),
  rejectionReason: z.string().nullable(),
  deactivationReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorBankAccount = z.infer<typeof VendorBankAccountSchema>;

export function parseVendorBankAccount(row: Record<string, unknown>): VendorBankAccount {
  return VendorBankAccountSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    accountFamilyId: row.account_family_id,
    accountHolderName: row.account_holder_name,
    bankName: row.bank_name,
    accountNumberLast4: row.account_number_last4,
    currency: row.currency,
    purpose: row.purpose,
    status: row.status,
    effectiveFrom: row.effective_from ?? null,
    evidenceFileId: row.evidence_file_id ?? null,
    isDuplicateCandidate: Boolean(row.is_duplicate_candidate),
    proposedBy: row.proposed_by ?? null,
    approvedBy: row.approved_by ?? null,
    holdReason: row.hold_reason ?? null,
    rejectionReason: row.rejection_reason ?? null,
    deactivationReason: row.deactivation_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.reveal_vendor_bank_account_number's own row shape -- the ONLY shape that ever carries the real decrypted bank account number. Never returned from a masked/list/search RPC. */
export const VendorBankAccountRevealSchema = z.object({
  bankAccountNumber: z.string(),
  accountHolderName: z.string(),
  bankName: z.string(),
  currency: z.string(),
  purpose: VendorBankAccountPurposeSchema,
  status: VendorFinancialLifecycleStatusSchema,
});
export type VendorBankAccountReveal = z.infer<typeof VendorBankAccountRevealSchema>;

export function parseVendorBankAccountReveal(row: Record<string, unknown>): VendorBankAccountReveal {
  return VendorBankAccountRevealSchema.parse({
    bankAccountNumber: row.account_number,
    accountHolderName: row.account_holder_name,
    bankName: row.bank_name,
    currency: row.currency,
    purpose: row.purpose,
    status: row.status,
  });
}

/** app.get_vendor_tax_identity_masked / app.list_vendor_tax_identities_masked's own row shape. */
export const VendorTaxIdentitySchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  taxFamilyId: z.string().uuid(),
  taxIdType: z.string(),
  taxIdLast4: z.string(),
  legalNameOnFile: z.string(),
  status: VendorFinancialLifecycleStatusSchema,
  effectiveFrom: z.string().nullable(),
  evidenceFileId: z.string().uuid().nullable(),
  isDuplicateCandidate: z.boolean(),
  proposedBy: z.string().nullable(),
  approvedBy: z.string().nullable(),
  holdReason: z.string().nullable(),
  rejectionReason: z.string().nullable(),
  deactivationReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorTaxIdentity = z.infer<typeof VendorTaxIdentitySchema>;

export function parseVendorTaxIdentity(row: Record<string, unknown>): VendorTaxIdentity {
  return VendorTaxIdentitySchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    taxFamilyId: row.tax_family_id,
    taxIdType: row.tax_id_type,
    taxIdLast4: row.tax_id_last4,
    legalNameOnFile: row.legal_name_on_file,
    status: row.status,
    effectiveFrom: row.effective_from ?? null,
    evidenceFileId: row.evidence_file_id ?? null,
    isDuplicateCandidate: Boolean(row.is_duplicate_candidate),
    proposedBy: row.proposed_by ?? null,
    approvedBy: row.approved_by ?? null,
    holdReason: row.hold_reason ?? null,
    rejectionReason: row.rejection_reason ?? null,
    deactivationReason: row.deactivation_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.reveal_vendor_tax_identity_number's own row shape -- the ONLY shape that ever carries the real decrypted tax identifier. See this file's own header for the disclosed logger-redaction naming gap for this specific field. */
export const VendorTaxIdentityRevealSchema = z.object({
  taxIdNumber: z.string(),
  taxIdType: z.string(),
  legalNameOnFile: z.string(),
  status: VendorFinancialLifecycleStatusSchema,
});
export type VendorTaxIdentityReveal = z.infer<typeof VendorTaxIdentityRevealSchema>;

export function parseVendorTaxIdentityReveal(row: Record<string, unknown>): VendorTaxIdentityReveal {
  return VendorTaxIdentityRevealSchema.parse({
    taxIdNumber: row.tax_id,
    taxIdType: row.tax_id_type,
    legalNameOnFile: row.legal_name_on_file,
    status: row.status,
  });
}

/** app.get_vendor_payment_term_proposal / app.list_vendor_payment_term_proposals' own row shape -- a proposal/approval pair over app.vendor_profiles.payment_term_days (design note 10), never a new master. */
export const VENDOR_PAYMENT_TERM_PROPOSAL_STATUSES = ["pending_approval", "approved", "rejected"] as const;
export const VendorPaymentTermProposalStatusSchema = z.enum(VENDOR_PAYMENT_TERM_PROPOSAL_STATUSES);
export type VendorPaymentTermProposalStatus = z.infer<typeof VendorPaymentTermProposalStatusSchema>;

export const VendorPaymentTermProposalSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  currentPaymentTermDays: z.number().int().nullable(),
  proposedPaymentTermDays: z.number().int().nonnegative(),
  vendorProfileExpectedVersion: z.number().int().positive(),
  reason: z.string(),
  status: VendorPaymentTermProposalStatusSchema,
  proposedBy: z.string().nullable(),
  approvedBy: z.string().nullable(),
  reauthConfirmedAt: z.string().nullable(),
  decisionReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorPaymentTermProposal = z.infer<typeof VendorPaymentTermProposalSchema>;

export function parseVendorPaymentTermProposal(row: Record<string, unknown>): VendorPaymentTermProposal {
  return VendorPaymentTermProposalSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    currentPaymentTermDays: row.current_payment_term_days ?? null,
    proposedPaymentTermDays: row.proposed_payment_term_days,
    vendorProfileExpectedVersion: row.vendor_profile_expected_version,
    reason: row.reason,
    status: row.status,
    proposedBy: row.proposed_by ?? null,
    approvedBy: row.approved_by ?? null,
    reauthConfirmedAt: row.reauth_confirmed_at ?? null,
    decisionReason: row.decision_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** app.get_vendor_financial_verification_status's own row -- the single downstream-composable read (Sec.13/33) a future Finance/Sourcing/PO/invoice-matching capability composes against. Never composed here; never writes to any app.finance_* table; never mutates app.vendor_profiles.lifecycle_status. */
export const VendorFinancialVerificationStatusSchema = z.object({
  vendorMasterRecordId: z.string().uuid(),
  hasVerifiedBankAccount: z.boolean(),
  hasVerifiedTaxIdentity: z.boolean(),
  onHold: z.boolean(),
  computedAt: z.string(),
});
export type VendorFinancialVerificationStatus = z.infer<typeof VendorFinancialVerificationStatusSchema>;

export function parseVendorFinancialVerificationStatus(row: Record<string, unknown>): VendorFinancialVerificationStatus {
  return VendorFinancialVerificationStatusSchema.parse({
    vendorMasterRecordId: row.vendor_master_record_id,
    hasVerifiedBankAccount: Boolean(row.has_verified_bank_account),
    hasVerifiedTaxIdentity: Boolean(row.has_verified_tax_identity),
    onHold: Boolean(row.on_hold),
    computedAt: row.computed_at,
  });
}

/** Shared shape for app.access_vendor_bank_account_evidence / app.access_vendor_tax_identity_evidence -- composes PRC:Download authority with PLT-128's own app.authorize_file_access. A denied result nulls out every file-identifying field -- including fileId itself when the caller never held PRC:Download at all (security-rls fix: an authority-denied caller must not learn whether evidence is attached from a non-null file_id). Never carries storage_path. */
export const VendorFinancialEvidenceAccessSchema = z.object({
  fileId: z.string().uuid().nullable(),
  originalFilename: z.string().nullable(),
  mimeType: z.string().nullable(),
  sizeBytes: z.number().int().nonnegative().nullable(),
  malwareScanStatus: z.string().nullable(),
  classification: z.string().nullable(),
  legalHold: z.boolean().nullable(),
  uploadedAt: z.string().nullable(),
  accessResult: VendorFinancialAccessResultSchema,
  accessReason: z.string().nullable(),
});
export type VendorFinancialEvidenceAccess = z.infer<typeof VendorFinancialEvidenceAccessSchema>;

export function parseVendorFinancialEvidenceAccess(row: Record<string, unknown>): VendorFinancialEvidenceAccess {
  return VendorFinancialEvidenceAccessSchema.parse({
    fileId: row.file_id ?? null,
    originalFilename: row.original_filename ?? null,
    mimeType: row.mime_type ?? null,
    sizeBytes: row.size_bytes === null || row.size_bytes === undefined ? null : Number(row.size_bytes),
    malwareScanStatus: row.malware_scan_status ?? null,
    classification: row.classification ?? null,
    legalHold: row.legal_hold ?? null,
    uploadedAt: row.uploaded_at ?? null,
    accessResult: row.access_result,
    accessReason: row.access_reason ?? null,
  });
}

// --- Mutation inputs ---

const actorFields = {
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
};

// A reauth timestamp: an ISO string the caller's own client-side re-authentication
// step is assumed to have just produced. Freshness (<=5 minutes, not in the future)
// is enforced server-side by the RPC itself (design notes 6-7) -- this schema only
// checks shape, never re-derives freshness client-side (the server clock is
// authoritative).
const reauthField = { reauthConfirmedAt: z.string() };

// --- Bank account lifecycle ---

export const CreateVendorBankAccountDraftInputSchema = z.object({
  vendorMasterRecordId: z.string().uuid(),
  accountHolderName: z.string().min(1),
  bankName: z.string().min(1),
  bankAccountNumber: z.string().min(4),
  currency: z.string().length(3),
  purpose: VendorBankAccountPurposeSchema.optional(),
  effectiveFrom: z.string().nullable().optional(),
  evidenceFileId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type CreateVendorBankAccountDraftInput = z.infer<typeof CreateVendorBankAccountDraftInputSchema>;

export const UpdateVendorBankAccountDraftInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  accountHolderName: z.string().min(1),
  bankName: z.string().min(1),
  bankAccountNumber: z.string().min(4),
  currency: z.string().length(3),
  purpose: VendorBankAccountPurposeSchema.optional(),
  effectiveFrom: z.string().nullable().optional(),
  evidenceFileId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type UpdateVendorBankAccountDraftInput = z.infer<typeof UpdateVendorBankAccountDraftInputSchema>;

export const SubmitVendorBankAccountForApprovalInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  ...actorFields,
});
export type SubmitVendorBankAccountForApprovalInput = z.infer<typeof SubmitVendorBankAccountForApprovalInputSchema>;

/** Input to the mandatory maker-checker + MFA decision RPC (design notes 6-7). reauthConfirmedAt must be fresh (<=5 minutes, server-enforced). */
export const DecideVendorBankAccountApprovalInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: VendorFinancialDecisionSchema,
  supersedesAccountId: z.string().uuid().nullable().optional(),
  rejectionReason: z.string().nullable().optional(),
  ...reauthField,
  ...actorFields,
});
export type DecideVendorBankAccountApprovalInput = z.infer<typeof DecideVendorBankAccountApprovalInputSchema>;

/** spec-compliance fix: hold/reactivate/deactivate now require the same MFA reauth freshness proof as decide/reveal (Sec.24 -- these RPCs mutate the record's own effective, downstream-consumed verification status). */
export const HoldVendorBankAccountInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  ...reauthField,
  ...actorFields,
});
export type HoldVendorBankAccountInput = z.infer<typeof HoldVendorBankAccountInputSchema>;

/** reauthConfirmedAt is required; the RPC additionally rejects reactivation by the same identity that placed the hold (self_reactivation_not_allowed). */
export const ReactivateVendorBankAccountInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  ...reauthField,
  ...actorFields,
});
export type ReactivateVendorBankAccountInput = z.infer<typeof ReactivateVendorBankAccountInputSchema>;

export const DeactivateVendorBankAccountInputSchema = z.object({
  accountId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  ...reauthField,
  ...actorFields,
});
export type DeactivateVendorBankAccountInput = z.infer<typeof DeactivateVendorBankAccountInputSchema>;

/** Input to the privileged, purpose-bound, MFA-gated reveal (design note 6). revealReason is mandatory (purpose-bound, Sec.16) -- the reveal is itself an audited event, never a passive read. */
export const RevealVendorBankAccountNumberInputSchema = z.object({
  accountId: z.string().uuid(),
  revealReason: z.string().min(1),
  correlationId: z.string().uuid().nullable().optional(),
  ...reauthField,
  ...actorFields,
});
export type RevealVendorBankAccountNumberInput = z.infer<typeof RevealVendorBankAccountNumberInputSchema>;

export const AccessVendorBankAccountEvidenceInputSchema = z.object({
  accountId: z.string().uuid(),
  accessType: VendorFinancialAccessTypeSchema,
  correlationId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type AccessVendorBankAccountEvidenceInput = z.infer<typeof AccessVendorBankAccountEvidenceInputSchema>;

// --- Tax identity lifecycle (mirrors bank account exactly, one field-set down) ---

export const CreateVendorTaxIdentityDraftInputSchema = z.object({
  vendorMasterRecordId: z.string().uuid(),
  taxIdType: z.string().min(1),
  taxIdNumber: z.string().min(4),
  legalNameOnFile: z.string().min(1),
  effectiveFrom: z.string().nullable().optional(),
  evidenceFileId: z.string().uuid().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type CreateVendorTaxIdentityDraftInput = z.infer<typeof CreateVendorTaxIdentityDraftInputSchema>;

export const UpdateVendorTaxIdentityDraftInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  taxIdType: z.string().min(1),
  taxIdNumber: z.string().min(4),
  legalNameOnFile: z.string().min(1),
  effectiveFrom: z.string().nullable().optional(),
  evidenceFileId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type UpdateVendorTaxIdentityDraftInput = z.infer<typeof UpdateVendorTaxIdentityDraftInputSchema>;

export const SubmitVendorTaxIdentityForApprovalInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  ...actorFields,
});
export type SubmitVendorTaxIdentityForApprovalInput = z.infer<typeof SubmitVendorTaxIdentityForApprovalInputSchema>;

export const DecideVendorTaxIdentityApprovalInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: VendorFinancialDecisionSchema,
  supersedesTaxIdentityId: z.string().uuid().nullable().optional(),
  rejectionReason: z.string().nullable().optional(),
  ...reauthField,
  ...actorFields,
});
export type DecideVendorTaxIdentityApprovalInput = z.infer<typeof DecideVendorTaxIdentityApprovalInputSchema>;

export const HoldVendorTaxIdentityInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  ...reauthField,
  ...actorFields,
});
export type HoldVendorTaxIdentityInput = z.infer<typeof HoldVendorTaxIdentityInputSchema>;

export const ReactivateVendorTaxIdentityInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  ...reauthField,
  ...actorFields,
});
export type ReactivateVendorTaxIdentityInput = z.infer<typeof ReactivateVendorTaxIdentityInputSchema>;

export const DeactivateVendorTaxIdentityInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  ...reauthField,
  ...actorFields,
});
export type DeactivateVendorTaxIdentityInput = z.infer<typeof DeactivateVendorTaxIdentityInputSchema>;

export const RevealVendorTaxIdentityNumberInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  revealReason: z.string().min(1),
  correlationId: z.string().uuid().nullable().optional(),
  ...reauthField,
  ...actorFields,
});
export type RevealVendorTaxIdentityNumberInput = z.infer<typeof RevealVendorTaxIdentityNumberInputSchema>;

export const AccessVendorTaxIdentityEvidenceInputSchema = z.object({
  taxIdentityId: z.string().uuid(),
  accessType: VendorFinancialAccessTypeSchema,
  correlationId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type AccessVendorTaxIdentityEvidenceInput = z.infer<typeof AccessVendorTaxIdentityEvidenceInputSchema>;

// --- Payment-term change proposal/approval (design note 10) ---

export const ProposeVendorPaymentTermChangeInputSchema = z.object({
  vendorMasterRecordId: z.string().uuid(),
  proposedPaymentTermDays: z.number().int().nonnegative(),
  reason: z.string().min(1),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type ProposeVendorPaymentTermChangeInput = z.infer<typeof ProposeVendorPaymentTermChangeInputSchema>;

export const DecideVendorPaymentTermChangeProposalInputSchema = z.object({
  proposalId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: VendorFinancialDecisionSchema,
  decisionReason: z.string().nullable().optional(),
  ...reauthField,
  ...actorFields,
});
export type DecideVendorPaymentTermChangeProposalInput = z.infer<typeof DecideVendorPaymentTermChangeProposalInputSchema>;
