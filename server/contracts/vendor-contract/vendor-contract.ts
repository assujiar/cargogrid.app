/**
 * Vendor Contract contract (PRC-261, CG-S11-PRC-012). Mirrors
 * supabase/migrations/20260730700000_create_procurement_vendor_contract.sql -- Zod
 * schemas + parse functions for VendorContract (cost-masked: rateVersionId/
 * paymentTermDays/taxTerms/capacityTerms are the four fields app.mask_vendor_contract_
 * cost_fields nulls for a caller without PRC:View cost, mirrors PurchaseOrderSchema's
 * own costMasked-flag shape) and VendorContractEvent, plus one *InputSchema per
 * mutation, the same shape server/contracts/purchase-order/purchase-order.ts already
 * establishes for this checkpoint's own template.
 */

import { z } from "zod";

export const VENDOR_CONTRACT_STATUSES = ["draft", "pending_approval", "active", "rejected", "suspended", "terminated", "superseded", "cancelled"] as const;
export const VendorContractStatusSchema = z.enum(VENDOR_CONTRACT_STATUSES);
export type VendorContractStatus = z.infer<typeof VendorContractStatusSchema>;

export const VENDOR_CONTRACT_TYPES = ["framework", "fixed_term"] as const;
export const VendorContractTypeSchema = z.enum(VENDOR_CONTRACT_TYPES);
export type VendorContractType = z.infer<typeof VendorContractTypeSchema>;

export const VENDOR_CONTRACT_VERSION_KINDS = ["initial", "amendment", "renewal"] as const;
export const VendorContractVersionKindSchema = z.enum(VENDOR_CONTRACT_VERSION_KINDS);
export type VendorContractVersionKind = z.infer<typeof VendorContractVersionKindSchema>;

export const VENDOR_CONTRACT_SIGNATURE_STATUSES = ["not_required", "pending", "signed"] as const;
export const VendorContractSignatureStatusSchema = z.enum(VENDOR_CONTRACT_SIGNATURE_STATUSES);
export type VendorContractSignatureStatus = z.infer<typeof VendorContractSignatureStatusSchema>;

export const VENDOR_CONTRACT_APPROVAL_STATUSES = ["not_required", "pending", "approved", "rejected"] as const;
export const VendorContractApprovalStatusSchema = z.enum(VENDOR_CONTRACT_APPROVAL_STATUSES);
export type VendorContractApprovalStatus = z.infer<typeof VendorContractApprovalStatusSchema>;

export const VendorContractSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  contractNumber: z.string(),
  versionNo: z.number().int().positive(),
  versionKind: VendorContractVersionKindSchema,
  contractType: VendorContractTypeSchema,
  status: VendorContractStatusSchema,
  effectiveStart: z.string(),
  effectiveEnd: z.string().nullable(),
  rateVersionId: z.string().uuid().nullable(),
  paymentTermDays: z.number().int().nullable(),
  taxTerms: z.record(z.string(), z.unknown()),
  slaTerms: z.record(z.string(), z.unknown()),
  capacityTerms: z.record(z.string(), z.unknown()),
  coverageTerms: z.record(z.string(), z.unknown()),
  complianceRequired: z.array(z.unknown()),
  termsDocumentFileId: z.string().uuid().nullable(),
  signatureRequired: z.boolean(),
  signatureStatus: VendorContractSignatureStatusSchema,
  signedBy: z.string().nullable(),
  signedAt: z.string().nullable(),
  approvalRequestId: z.string().uuid().nullable(),
  approvalStatus: VendorContractApprovalStatusSchema,
  supersedesContractId: z.string().uuid().nullable(),
  amendReason: z.string().nullable(),
  terminationReason: z.string().nullable(),
  terminationEvidenceRef: z.string().nullable(),
  terminatedAt: z.string().nullable(),
  cancelReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorContract = z.infer<typeof VendorContractSchema>;

/** True whenever the four cost-shaped fields are structurally masked (null/{}) -- mirrors PurchaseOrderSchema's own costMasked-derivation-from-nulls shape (the RPC itself never returns an explicit flag; it nulls the fields directly). */
export function isVendorContractCostMasked(row: Record<string, unknown>): boolean {
  return row.rate_version_id === null && row.payment_term_days === null && JSON.stringify(row.tax_terms ?? {}) === "{}" && JSON.stringify(row.capacity_terms ?? {}) === "{}";
}

export function parseVendorContract(row: Record<string, unknown>): VendorContract {
  return VendorContractSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterId: row.vendor_master_id,
    contractNumber: row.contract_number,
    versionNo: row.version_no,
    versionKind: row.version_kind,
    contractType: row.contract_type,
    status: row.status,
    effectiveStart: row.effective_start,
    effectiveEnd: row.effective_end,
    rateVersionId: row.rate_version_id,
    paymentTermDays: row.payment_term_days,
    taxTerms: row.tax_terms ?? {},
    slaTerms: row.sla_terms ?? {},
    capacityTerms: row.capacity_terms ?? {},
    coverageTerms: row.coverage_terms ?? {},
    complianceRequired: row.compliance_required ?? [],
    termsDocumentFileId: row.terms_document_file_id,
    signatureRequired: row.signature_required,
    signatureStatus: row.signature_status,
    signedBy: row.signed_by,
    signedAt: row.signed_at,
    approvalRequestId: row.approval_request_id,
    approvalStatus: row.approval_status,
    supersedesContractId: row.supersedes_contract_id,
    amendReason: row.amend_reason,
    terminationReason: row.termination_reason,
    terminationEvidenceRef: row.termination_evidence_ref,
    terminatedAt: row.terminated_at,
    cancelReason: row.cancel_reason,
    recordVersion: row.record_version,
    createdBy: row.created_by,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorContractEventSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  contractId: z.string().uuid(),
  fromStatus: z.string(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  actorAuthUserId: z.string().uuid().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type VendorContractEvent = z.infer<typeof VendorContractEventSchema>;

export function parseVendorContractEvent(row: Record<string, unknown>): VendorContractEvent {
  return VendorContractEventSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    contractId: row.contract_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason,
    actorAuthUserId: row.actor_auth_user_id,
    actorLabel: row.actor_label,
    occurredAt: row.occurred_at,
  });
}

// -- Mutation inputs -------------------------------------------------------

export const CreateVendorContractDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorMasterId: z.string().uuid(),
  contractType: VendorContractTypeSchema,
  effectiveStart: z.string().min(1),
  effectiveEnd: z.string().nullable().default(null),
  rateVersionId: z.string().uuid().nullable().default(null),
  paymentTermDays: z.number().int().nonnegative().nullable().default(null),
  taxTerms: z.record(z.string(), z.unknown()).default({}),
  slaTerms: z.record(z.string(), z.unknown()).default({}),
  capacityTerms: z.record(z.string(), z.unknown()).default({}),
  coverageTerms: z.record(z.string(), z.unknown()).default({}),
  complianceRequired: z.array(z.string()).default([]),
  signatureRequired: z.boolean().default(true),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CreateVendorContractDraftInput = z.input<typeof CreateVendorContractDraftInputSchema>;

// Every *Terms/complianceRequired field is nullable, defaulting to null -- the RPC's
// own `coalesce(p_field, existing_field)` shape means null means "leave unchanged",
// never "clear to empty" (a real bug caught in this prompt's own Tier B self-check:
// defaulting these to {}/[] here would silently overwrite real prior terms on every
// edit that doesn't explicitly resend them, since {} is NOT NULL for coalesce).
export const UpdateVendorContractDraftInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  effectiveStart: z.string().min(1),
  effectiveEnd: z.string().nullable().default(null),
  rateVersionId: z.string().uuid().nullable().default(null),
  paymentTermDays: z.number().int().nonnegative().nullable().default(null),
  taxTerms: z.record(z.string(), z.unknown()).nullable().default(null),
  slaTerms: z.record(z.string(), z.unknown()).nullable().default(null),
  capacityTerms: z.record(z.string(), z.unknown()).nullable().default(null),
  coverageTerms: z.record(z.string(), z.unknown()).nullable().default(null),
  complianceRequired: z.array(z.string()).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type UpdateVendorContractDraftInput = z.input<typeof UpdateVendorContractDraftInputSchema>;

export const SubmitVendorContractForApprovalInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  idempotencyKey: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SubmitVendorContractForApprovalInput = z.input<typeof SubmitVendorContractForApprovalInputSchema>;

export const RecordVendorContractSignatureInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  signedBy: z.string().min(1),
  signedAt: z.string().nullable().default(null),
  evidenceFileId: z.string().uuid().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RecordVendorContractSignatureInput = z.input<typeof RecordVendorContractSignatureInputSchema>;

export const ActivateVendorContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ActivateVendorContractInput = z.input<typeof ActivateVendorContractInputSchema>;

export const AmendVendorContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  effectiveEnd: z.string().nullable().default(null),
  rateVersionId: z.string().uuid().nullable().default(null),
  paymentTermDays: z.number().int().nonnegative().nullable().default(null),
  slaTerms: z.record(z.string(), z.unknown()).nullable().default(null),
  capacityTerms: z.record(z.string(), z.unknown()).nullable().default(null),
  coverageTerms: z.record(z.string(), z.unknown()).nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type AmendVendorContractInput = z.input<typeof AmendVendorContractInputSchema>;

export const RenewVendorContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  newEffectiveStart: z.string().min(1),
  newEffectiveEnd: z.string().nullable().default(null),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type RenewVendorContractInput = z.input<typeof RenewVendorContractInputSchema>;

export const SuspendVendorContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type SuspendVendorContractInput = z.input<typeof SuspendVendorContractInputSchema>;

export const ReactivateVendorContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type ReactivateVendorContractInput = z.input<typeof ReactivateVendorContractInputSchema>;

export const TerminateVendorContractInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  evidenceRef: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type TerminateVendorContractInput = z.input<typeof TerminateVendorContractInputSchema>;

export const CancelVendorContractDraftInputSchema = z.object({
  contractId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
});
export type CancelVendorContractDraftInput = z.input<typeof CancelVendorContractDraftInputSchema>;
