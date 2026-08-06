/**
 * Vendor Compliance and Document Expiry contract (PRC-253, CG-S11-PRC-004). Mirrors
 * supabase/migrations/20260730600000_create_procurement_vendor_compliance.sql's
 * app.vendor_compliance_requirements/app.vendor_compliance_documents/
 * app.vendor_compliance_waivers/app.vendor_compliance_status shapes and their RPCs.
 * Follows the exact directory convention PRC-251/252 established: Zod schemas here,
 * list/read projections in server/queries/vendor-compliance.ts, RPC-calling mutation
 * wrappers with an enumerated error-code type in server/mutations/vendor-compliance.ts.
 *
 * app.vendor_compliance_documents/app.vendor_compliance_waivers/
 * app.vendor_compliance_status.vendor_master_record_id references
 * app.vendor_profiles.master_record_id (PRC-251) -- the single canonical vendor
 * identity (ADR-0020). This capability never mutates
 * app.vendor_profiles.lifecycle_status; app.get_vendor_compliance_eligibility is the
 * downstream-composable read a future sourcing/PO/assignment capability (256+)
 * composes against.
 */

import { z } from "zod";

export const VENDOR_COMPLIANCE_REQUIREMENT_STATUSES = ["draft", "published", "archived"] as const;
export const VendorComplianceRequirementStatusSchema = z.enum(VENDOR_COMPLIANCE_REQUIREMENT_STATUSES);
export type VendorComplianceRequirementStatus = z.infer<typeof VendorComplianceRequirementStatusSchema>;

export const VENDOR_COMPLIANCE_BLOCKING_EFFECTS = ["blocking", "warning"] as const;
export const VendorComplianceBlockingEffectSchema = z.enum(VENDOR_COMPLIANCE_BLOCKING_EFFECTS);
export type VendorComplianceBlockingEffect = z.infer<typeof VendorComplianceBlockingEffectSchema>;

export const VENDOR_COMPLIANCE_DOCUMENT_VERIFICATION_STATUSES = ["pending", "verified", "rejected", "revision_requested"] as const;
export const VendorComplianceDocumentVerificationStatusSchema = z.enum(VENDOR_COMPLIANCE_DOCUMENT_VERIFICATION_STATUSES);
export type VendorComplianceDocumentVerificationStatus = z.infer<typeof VendorComplianceDocumentVerificationStatusSchema>;

export const VENDOR_COMPLIANCE_DOCUMENT_DECISIONS = ["verified", "rejected", "revision_requested"] as const;
export const VendorComplianceDocumentDecisionSchema = z.enum(VENDOR_COMPLIANCE_DOCUMENT_DECISIONS);
export type VendorComplianceDocumentDecision = z.infer<typeof VendorComplianceDocumentDecisionSchema>;

export const VENDOR_COMPLIANCE_WAIVER_STATUSES = ["pending", "approved", "rejected", "expired", "revoked"] as const;
export const VendorComplianceWaiverStatusSchema = z.enum(VENDOR_COMPLIANCE_WAIVER_STATUSES);
export type VendorComplianceWaiverStatus = z.infer<typeof VendorComplianceWaiverStatusSchema>;

export const VENDOR_COMPLIANCE_WAIVER_DECISIONS = ["approved", "rejected"] as const;
export const VendorComplianceWaiverDecisionSchema = z.enum(VENDOR_COMPLIANCE_WAIVER_DECISIONS);
export type VendorComplianceWaiverDecision = z.infer<typeof VendorComplianceWaiverDecisionSchema>;

export const VENDOR_COMPLIANCE_STATUSES = ["not_submitted", "pending_verification", "verified", "expiring_soon", "expired", "waived", "rejected"] as const;
export const VendorComplianceStatusValueSchema = z.enum(VENDOR_COMPLIANCE_STATUSES);
export type VendorComplianceStatusValue = z.infer<typeof VendorComplianceStatusValueSchema>;

// --- Core rows ---

export const VendorComplianceRequirementSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  requirementFamilyId: z.string().uuid(),
  vendorCategory: z.string().nullable(),
  serviceType: z.string().nullable(),
  documentTypeCode: z.string(),
  name: z.string(),
  description: z.string().nullable(),
  blockingEffect: VendorComplianceBlockingEffectSchema,
  requiresExpiry: z.boolean(),
  reminderOffsets: z.array(z.number().int()),
  status: VendorComplianceRequirementStatusSchema,
  supersedesVersionId: z.string().uuid().nullable(),
  effectiveFrom: z.string(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorComplianceRequirement = z.infer<typeof VendorComplianceRequirementSchema>;

export function parseVendorComplianceRequirement(row: Record<string, unknown>): VendorComplianceRequirement {
  return VendorComplianceRequirementSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    requirementFamilyId: row.requirement_family_id,
    vendorCategory: row.vendor_category ?? null,
    serviceType: row.service_type ?? null,
    documentTypeCode: row.document_type_code,
    name: row.name,
    description: row.description ?? null,
    blockingEffect: row.blocking_effect,
    requiresExpiry: Boolean(row.requires_expiry),
    reminderOffsets: Array.isArray(row.reminder_offsets) ? row.reminder_offsets.map((n) => Number(n)) : [],
    status: row.status,
    supersedesVersionId: row.supersedes_version_id ?? null,
    effectiveFrom: row.effective_from,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorComplianceDocumentSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  requirementVersionId: z.string().uuid(),
  fileId: z.string().uuid(),
  versionGroupId: z.string().uuid(),
  versionNumber: z.number().int().positive(),
  isLatestVersion: z.boolean(),
  issueDate: z.string().nullable(),
  expiryDate: z.string().nullable(),
  verificationStatus: VendorComplianceDocumentVerificationStatusSchema,
  verifiedBy: z.string().nullable(),
  verifiedByAuthUserId: z.string().uuid().nullable(),
  verifiedAt: z.string().nullable(),
  rejectionReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorComplianceDocument = z.infer<typeof VendorComplianceDocumentSchema>;

export function parseVendorComplianceDocument(row: Record<string, unknown>): VendorComplianceDocument {
  return VendorComplianceDocumentSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    requirementVersionId: row.requirement_version_id,
    fileId: row.file_id,
    versionGroupId: row.version_group_id,
    versionNumber: row.version_number,
    isLatestVersion: Boolean(row.is_latest_version),
    issueDate: row.issue_date ?? null,
    expiryDate: row.expiry_date ?? null,
    verificationStatus: row.verification_status,
    verifiedBy: row.verified_by ?? null,
    verifiedByAuthUserId: row.verified_by_auth_user_id ?? null,
    verifiedAt: row.verified_at ?? null,
    rejectionReason: row.rejection_reason ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorComplianceWaiverSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  requirementVersionId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  reason: z.string(),
  validFrom: z.string(),
  validUntil: z.string(),
  requestedBy: z.string().nullable(),
  requestedByAuthUserId: z.string().uuid(),
  approvedBy: z.string().nullable(),
  approvedByAuthUserId: z.string().uuid().nullable(),
  decisionReason: z.string().nullable(),
  status: VendorComplianceWaiverStatusSchema,
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorComplianceWaiver = z.infer<typeof VendorComplianceWaiverSchema>;

export function parseVendorComplianceWaiver(row: Record<string, unknown>): VendorComplianceWaiver {
  return VendorComplianceWaiverSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    requirementVersionId: row.requirement_version_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    reason: row.reason,
    validFrom: row.valid_from,
    validUntil: row.valid_until,
    requestedBy: row.requested_by ?? null,
    requestedByAuthUserId: row.requested_by_auth_user_id,
    approvedBy: row.approved_by ?? null,
    approvedByAuthUserId: row.approved_by_auth_user_id ?? null,
    decisionReason: row.decision_reason ?? null,
    status: row.status,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/** Raw app.vendor_compliance_status row -- one per (vendor, requirement FAMILY), survives a requirement republish. Written only by app._recalculate_vendor_compliance_status_family. */
export const VendorComplianceStatusRowSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  requirementFamilyId: z.string().uuid(),
  currentRequirementVersionId: z.string().uuid().nullable(),
  currentDocumentId: z.string().uuid().nullable(),
  status: VendorComplianceStatusValueSchema,
  eligibilityHold: z.boolean(),
  computedAt: z.string(),
  computedBy: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorComplianceStatusRow = z.infer<typeof VendorComplianceStatusRowSchema>;

export function parseVendorComplianceStatusRow(row: Record<string, unknown>): VendorComplianceStatusRow {
  return VendorComplianceStatusRowSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    requirementFamilyId: row.requirement_family_id,
    currentRequirementVersionId: row.current_requirement_version_id ?? null,
    currentDocumentId: row.current_document_id ?? null,
    status: row.status,
    eligibilityHold: Boolean(row.eligibility_hold),
    computedAt: row.computed_at,
    computedBy: row.computed_by ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

/**
 * app.get_vendor_compliance_eligibility's own row -- the downstream-composable read (Prompts 256+ compose eligibility against this; never composed here).
 * reminderOffsets/daysUntilExpiry/reminderTierDays (fix-pass addition, MEDIUM-severity
 * finding, adversarial review) are read-time-computed, never stored -- they surface
 * WHICH reminder tier a document has already crossed (the smallest already-triggered
 * offset) so a consumer can distinguish a 30-day-tier row from a 7-day-tier row
 * instead of collapsing every expiring_soon row into one undifferentiated bucket.
 */
export const VendorComplianceEligibilityRowSchema = z.object({
  requirementFamilyId: z.string().uuid(),
  requirementVersionId: z.string().uuid().nullable(),
  requirementName: z.string().nullable(),
  blockingEffect: VendorComplianceBlockingEffectSchema.nullable(),
  documentTypeCode: z.string().nullable(),
  status: VendorComplianceStatusValueSchema,
  eligibilityHold: z.boolean(),
  currentDocumentId: z.string().uuid().nullable(),
  expiryDate: z.string().nullable(),
  reminderOffsets: z.array(z.number().int()).nullable(),
  daysUntilExpiry: z.number().int().nullable(),
  reminderTierDays: z.number().int().nullable(),
  computedAt: z.string(),
});
export type VendorComplianceEligibilityRow = z.infer<typeof VendorComplianceEligibilityRowSchema>;

export function parseVendorComplianceEligibilityRow(row: Record<string, unknown>): VendorComplianceEligibilityRow {
  return VendorComplianceEligibilityRowSchema.parse({
    requirementFamilyId: row.requirement_family_id,
    requirementVersionId: row.requirement_version_id ?? null,
    requirementName: row.requirement_name ?? null,
    blockingEffect: row.blocking_effect ?? null,
    documentTypeCode: row.document_type_code ?? null,
    status: row.status,
    eligibilityHold: Boolean(row.eligibility_hold),
    currentDocumentId: row.current_document_id ?? null,
    expiryDate: row.expiry_date ?? null,
    reminderOffsets: Array.isArray(row.reminder_offsets) ? row.reminder_offsets.map((n) => Number(n)) : null,
    daysUntilExpiry: row.days_until_expiry === null || row.days_until_expiry === undefined ? null : Number(row.days_until_expiry),
    reminderTierDays: row.reminder_tier_days === null || row.reminder_tier_days === undefined ? null : Number(row.reminder_tier_days),
    computedAt: row.computed_at,
  });
}

/** app.list_tenant_vendor_compliance_matrix's own row -- the compliance-matrix and expiry/reminders-queue shared data source (server-filtered, cursor-paginated). reminderOffsets/daysUntilExpiry/reminderTierDays: see VendorComplianceEligibilityRowSchema's own doc comment -- identical fix-pass addition, same shared read RPC family. */
export const VendorComplianceMatrixRowSchema = z.object({
  statusId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  vendorLegalName: z.string(),
  requirementFamilyId: z.string().uuid(),
  requirementVersionId: z.string().uuid().nullable(),
  requirementName: z.string().nullable(),
  blockingEffect: VendorComplianceBlockingEffectSchema.nullable(),
  documentTypeCode: z.string().nullable(),
  status: VendorComplianceStatusValueSchema,
  eligibilityHold: z.boolean(),
  currentDocumentId: z.string().uuid().nullable(),
  expiryDate: z.string().nullable(),
  reminderOffsets: z.array(z.number().int()).nullable(),
  daysUntilExpiry: z.number().int().nullable(),
  reminderTierDays: z.number().int().nullable(),
  computedAt: z.string(),
});
export type VendorComplianceMatrixRow = z.infer<typeof VendorComplianceMatrixRowSchema>;

export function parseVendorComplianceMatrixRow(row: Record<string, unknown>): VendorComplianceMatrixRow {
  return VendorComplianceMatrixRowSchema.parse({
    statusId: row.status_id,
    vendorMasterRecordId: row.vendor_master_record_id,
    vendorLegalName: row.vendor_legal_name,
    requirementFamilyId: row.requirement_family_id,
    requirementVersionId: row.requirement_version_id ?? null,
    requirementName: row.requirement_name ?? null,
    blockingEffect: row.blocking_effect ?? null,
    documentTypeCode: row.document_type_code ?? null,
    status: row.status,
    eligibilityHold: Boolean(row.eligibility_hold),
    currentDocumentId: row.current_document_id ?? null,
    expiryDate: row.expiry_date ?? null,
    reminderOffsets: Array.isArray(row.reminder_offsets) ? row.reminder_offsets.map((n) => Number(n)) : null,
    daysUntilExpiry: row.days_until_expiry === null || row.days_until_expiry === undefined ? null : Number(row.days_until_expiry),
    reminderTierDays: row.reminder_tier_days === null || row.reminder_tier_days === undefined ? null : Number(row.reminder_tier_days),
    computedAt: row.computed_at,
  });
}

// --- Evidence access (fix-pass addition, HIGH-severity finding, adversarial review) ---

export const VENDOR_COMPLIANCE_ACCESS_TYPES = ["signed_url_issued", "download", "metadata_view"] as const;
export const VendorComplianceAccessTypeSchema = z.enum(VENDOR_COMPLIANCE_ACCESS_TYPES);
export type VendorComplianceAccessType = z.infer<typeof VendorComplianceAccessTypeSchema>;

export const VENDOR_COMPLIANCE_ACCESS_RESULTS = ["granted", "denied"] as const;
export const VendorComplianceAccessResultSchema = z.enum(VENDOR_COMPLIANCE_ACCESS_RESULTS);
export type VendorComplianceAccessResult = z.infer<typeof VendorComplianceAccessResultSchema>;

/** app.access_vendor_compliance_document_evidence's own row -- composes PRC:Download authority plus PLT-128's own app.authorize_file_access (malware-scan + record/sensitivity gate). A denied result nulls out every file-identifying field. Never carries storage_path. */
export const VendorComplianceDocumentEvidenceAccessSchema = z.object({
  fileId: z.string().uuid(),
  originalFilename: z.string().nullable(),
  mimeType: z.string().nullable(),
  sizeBytes: z.number().int().nonnegative().nullable(),
  malwareScanStatus: z.string().nullable(),
  classification: z.string().nullable(),
  legalHold: z.boolean().nullable(),
  uploadedAt: z.string().nullable(),
  accessResult: VendorComplianceAccessResultSchema,
  accessReason: z.string().nullable(),
});
export type VendorComplianceDocumentEvidenceAccess = z.infer<typeof VendorComplianceDocumentEvidenceAccessSchema>;

export function parseVendorComplianceDocumentEvidenceAccess(row: Record<string, unknown>): VendorComplianceDocumentEvidenceAccess {
  return VendorComplianceDocumentEvidenceAccessSchema.parse({
    fileId: row.file_id,
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

/** app.expire_vendor_compliance_waivers / app.recalculate_tenant_vendor_compliance_status's own bounded-sweep response shape. */
export const VendorComplianceSweepResultSchema = z.object({
  count: z.number().int().nonnegative(),
  moreRemaining: z.boolean(),
});
export type VendorComplianceSweepResult = z.infer<typeof VendorComplianceSweepResultSchema>;

// --- Mutation inputs ---

const actorFields = {
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string().min(1),
};

export const CreateVendorComplianceRequirementDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  vendorCategory: z.string().nullable().optional(),
  serviceType: z.string().nullable().optional(),
  documentTypeCode: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable().optional(),
  blockingEffect: VendorComplianceBlockingEffectSchema.optional(),
  requiresExpiry: z.boolean().optional(),
  reminderOffsets: z.array(z.number().int().positive()).nullable().optional(),
  effectiveFrom: z.string().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type CreateVendorComplianceRequirementDraftInput = z.infer<typeof CreateVendorComplianceRequirementDraftInputSchema>;

export const UpdateVendorComplianceRequirementDraftInputSchema = z.object({
  requirementVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  vendorCategory: z.string().nullable().optional(),
  serviceType: z.string().nullable().optional(),
  documentTypeCode: z.string().min(1),
  name: z.string().min(1),
  description: z.string().nullable().optional(),
  blockingEffect: VendorComplianceBlockingEffectSchema.optional(),
  requiresExpiry: z.boolean().optional(),
  reminderOffsets: z.array(z.number().int().positive()).nullable().optional(),
  effectiveFrom: z.string().nullable().optional(),
  ...actorFields,
});
export type UpdateVendorComplianceRequirementDraftInput = z.infer<typeof UpdateVendorComplianceRequirementDraftInputSchema>;

export const PublishVendorComplianceRequirementInputSchema = z.object({
  requirementVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  supersedesVersionId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type PublishVendorComplianceRequirementInput = z.infer<typeof PublishVendorComplianceRequirementInputSchema>;

export const ArchiveVendorComplianceRequirementInputSchema = z.object({
  requirementVersionId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  ...actorFields,
});
export type ArchiveVendorComplianceRequirementInput = z.infer<typeof ArchiveVendorComplianceRequirementInputSchema>;

export const SubmitVendorComplianceDocumentInputSchema = z.object({
  vendorMasterRecordId: z.string().uuid(),
  requirementVersionId: z.string().uuid(),
  fileId: z.string().uuid(),
  issueDate: z.string().nullable().optional(),
  expiryDate: z.string().nullable().optional(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type SubmitVendorComplianceDocumentInput = z.infer<typeof SubmitVendorComplianceDocumentInputSchema>;

export const RenewVendorComplianceDocumentInputSchema = z.object({
  previousDocumentId: z.string().uuid(),
  fileId: z.string().uuid(),
  issueDate: z.string().nullable().optional(),
  expiryDate: z.string().nullable().optional(),
  ...actorFields,
});
export type RenewVendorComplianceDocumentInput = z.infer<typeof RenewVendorComplianceDocumentInputSchema>;

export const DecideVendorComplianceDocumentInputSchema = z.object({
  documentId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: VendorComplianceDocumentDecisionSchema,
  rejectionReason: z.string().nullable().optional(),
  ...actorFields,
});
export type DecideVendorComplianceDocumentInput = z.infer<typeof DecideVendorComplianceDocumentInputSchema>;

/** Fix-pass addition: input to app.access_vendor_compliance_document_evidence -- the document/version viewer's own gated evidence-access call (PRC:Download + PLT-128's app.authorize_file_access). */
export const AccessVendorComplianceDocumentEvidenceInputSchema = z.object({
  documentId: z.string().uuid(),
  accessType: VendorComplianceAccessTypeSchema,
  correlationId: z.string().uuid().nullable().optional(),
  ...actorFields,
});
export type AccessVendorComplianceDocumentEvidenceInput = z.infer<typeof AccessVendorComplianceDocumentEvidenceInputSchema>;

export const RequestVendorComplianceWaiverInputSchema = z.object({
  requirementVersionId: z.string().uuid(),
  vendorMasterRecordId: z.string().uuid(),
  reason: z.string().min(1),
  validFrom: z.string(),
  validUntil: z.string(),
  idempotencyKey: z.string().nullable().optional(),
  ...actorFields,
});
export type RequestVendorComplianceWaiverInput = z.infer<typeof RequestVendorComplianceWaiverInputSchema>;

export const DecideVendorComplianceWaiverInputSchema = z.object({
  waiverId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: VendorComplianceWaiverDecisionSchema,
  decisionReason: z.string().nullable().optional(),
  ...actorFields,
});
export type DecideVendorComplianceWaiverInput = z.infer<typeof DecideVendorComplianceWaiverInputSchema>;

export const RevokeVendorComplianceWaiverInputSchema = z.object({
  waiverId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  reason: z.string().min(1),
  ...actorFields,
});
export type RevokeVendorComplianceWaiverInput = z.infer<typeof RevokeVendorComplianceWaiverInputSchema>;

export const ExpireVendorComplianceWaiversInputSchema = z.object({
  tenantId: z.string().uuid(),
  maxRows: z.number().int().positive().max(5000).optional(),
  ...actorFields,
});
export type ExpireVendorComplianceWaiversInput = z.infer<typeof ExpireVendorComplianceWaiversInputSchema>;

export const RecalculateVendorComplianceStatusInputSchema = z.object({
  vendorMasterRecordId: z.string().uuid(),
  ...actorFields,
});
export type RecalculateVendorComplianceStatusInput = z.infer<typeof RecalculateVendorComplianceStatusInputSchema>;

export const RecalculateTenantVendorComplianceStatusInputSchema = z.object({
  tenantId: z.string().uuid(),
  maxVendors: z.number().int().positive().max(2000).optional(),
  ...actorFields,
});
export type RecalculateTenantVendorComplianceStatusInput = z.infer<typeof RecalculateTenantVendorComplianceStatusInputSchema>;
