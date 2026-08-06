/**
 * Vendor Profile contract (PRC-251, CG-S11-PRC-002). Mirrors
 * supabase/migrations/20260730580000_create_procurement_vendor_registration.sql's
 * app.vendor_profiles/app.vendor_contacts/app.vendor_addresses/app.vendor_services/
 * app.vendor_coverage/app.vendor_profile_lifecycle_events/app.vendor_duplicate_
 * candidates/app.vendor_intake_tokens shapes and their RPCs. Follows the exact
 * directory convention ATW-229 (warehouse/zone) established: Zod schemas here,
 * list/read projections in server/queries/vendor-profile.ts, RPC-calling mutation
 * wrappers with an enumerated error-code type in server/mutations/vendor-profile.ts.
 *
 * app.vendor_profiles is a governed 1:1 extension of app.master_records where
 * master_type_code='vendor' (ADR-0020) -- the single canonical vendor identity. Every
 * schema below keys off master_record_id, never a second vendor identity.
 */

import { z } from "zod";

export const VENDOR_LIFECYCLE_STATUSES = ["draft", "submitted", "under_review", "approved", "active", "suspended", "archived", "blacklisted"] as const;
export const VendorLifecycleStatusSchema = z.enum(VENDOR_LIFECYCLE_STATUSES);
export type VendorLifecycleStatus = z.infer<typeof VendorLifecycleStatusSchema>;

export const VENDOR_INTAKE_SOURCES = ["staff_created", "invited", "self_registered", "bulk_import"] as const;
export const VendorIntakeSourceSchema = z.enum(VENDOR_INTAKE_SOURCES);
export type VendorIntakeSource = z.infer<typeof VendorIntakeSourceSchema>;

export const VENDOR_ADDRESS_TYPES = ["legal", "billing", "operational"] as const;
export const VendorAddressTypeSchema = z.enum(VENDOR_ADDRESS_TYPES);
export type VendorAddressType = z.infer<typeof VendorAddressTypeSchema>;

export const VENDOR_DUPLICATE_DECISIONS = ["pending", "linked", "dismissed"] as const;
export const VendorDuplicateDecisionSchema = z.enum(VENDOR_DUPLICATE_DECISIONS);
export type VendorDuplicateDecision = z.infer<typeof VendorDuplicateDecisionSchema>;

export const VENDOR_INTAKE_TOKEN_STATUSES = ["pending", "redeemed", "revoked", "expired"] as const;
export const VendorIntakeTokenStatusSchema = z.enum(VENDOR_INTAKE_TOKEN_STATUSES);
export type VendorIntakeTokenStatus = z.infer<typeof VendorIntakeTokenStatusSchema>;

export const VENDOR_REVIEW_DECISIONS = ["approve", "reject"] as const;
export const VendorReviewDecisionSchema = z.enum(VENDOR_REVIEW_DECISIONS);
export type VendorReviewDecision = z.infer<typeof VendorReviewDecisionSchema>;

// --- Core rows ---

export const VendorProfileSchema = z.object({
  masterRecordId: z.string().uuid(),
  tenantId: z.string().uuid(),
  vendorCode: z.string(),
  legalName: z.string(),
  tradeName: z.string().nullable(),
  legalEntityType: z.string().nullable(),
  businessRegistrationNumber: z.string().nullable(),
  vendorCategory: z.string().nullable(),
  paymentTermDays: z.number().int().nullable(),
  intakeSource: VendorIntakeSourceSchema,
  lifecycleStatus: VendorLifecycleStatusSchema,
  revisionReason: z.string().nullable(),
  suspendReason: z.string().nullable(),
  blacklistReason: z.string().nullable(),
  blacklistEvidenceRef: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
  contactCount: z.number().int(),
  addressCount: z.number().int(),
  serviceCount: z.number().int(),
  coverageCount: z.number().int(),
  pendingDuplicateCount: z.number().int(),
});
export type VendorProfile = z.infer<typeof VendorProfileSchema>;

export function parseVendorProfile(row: Record<string, unknown>): VendorProfile {
  return VendorProfileSchema.parse({
    masterRecordId: row.master_record_id,
    tenantId: row.tenant_id,
    vendorCode: row.vendor_code,
    legalName: row.legal_name,
    tradeName: row.trade_name ?? null,
    legalEntityType: row.legal_entity_type ?? null,
    businessRegistrationNumber: row.business_registration_number ?? null,
    vendorCategory: row.vendor_category ?? null,
    paymentTermDays: row.payment_term_days ?? null,
    intakeSource: row.intake_source,
    lifecycleStatus: row.lifecycle_status,
    revisionReason: row.revision_reason ?? null,
    suspendReason: row.suspend_reason ?? null,
    blacklistReason: row.blacklist_reason ?? null,
    blacklistEvidenceRef: row.blacklist_evidence_ref ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
    contactCount: row.contact_count,
    addressCount: row.address_count,
    serviceCount: row.service_count,
    coverageCount: row.coverage_count,
    pendingDuplicateCount: row.pending_duplicate_count,
  });
}

/**
 * A lifecycle-transition mutation RPC (create_vendor_profile_draft, submit_..., etc.)
 * returns the raw app.vendor_profiles row -- no vendor_code/counts joined in. This
 * narrower schema/parse pair is deliberately distinct from VendorProfileSchema, the
 * same "mutation responses never carry a read-projection's extra joined columns"
 * boundary server/contracts/warehouse-zone/warehouse-zone.ts already established for
 * parseWarehouse vs. TenantWarehouseListRowSchema.
 */
export const VendorProfileMutationResultSchema = z.object({
  masterRecordId: z.string().uuid(),
  tenantId: z.string().uuid(),
  legalName: z.string(),
  tradeName: z.string().nullable(),
  legalEntityType: z.string().nullable(),
  businessRegistrationNumber: z.string().nullable(),
  vendorCategory: z.string().nullable(),
  paymentTermDays: z.number().int().nullable(),
  intakeSource: VendorIntakeSourceSchema,
  lifecycleStatus: VendorLifecycleStatusSchema,
  revisionReason: z.string().nullable(),
  suspendReason: z.string().nullable(),
  blacklistReason: z.string().nullable(),
  blacklistEvidenceRef: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorProfileMutationResult = z.infer<typeof VendorProfileMutationResultSchema>;

export function parseVendorProfileMutationResult(row: Record<string, unknown>): VendorProfileMutationResult {
  return VendorProfileMutationResultSchema.parse({
    masterRecordId: row.master_record_id,
    tenantId: row.tenant_id,
    legalName: row.legal_name,
    tradeName: row.trade_name ?? null,
    legalEntityType: row.legal_entity_type ?? null,
    businessRegistrationNumber: row.business_registration_number ?? null,
    vendorCategory: row.vendor_category ?? null,
    paymentTermDays: row.payment_term_days ?? null,
    intakeSource: row.intake_source,
    lifecycleStatus: row.lifecycle_status,
    revisionReason: row.revision_reason ?? null,
    suspendReason: row.suspend_reason ?? null,
    blacklistReason: row.blacklist_reason ?? null,
    blacklistEvidenceRef: row.blacklist_evidence_ref ?? null,
    recordVersion: row.record_version,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorProfileListRowSchema = z.object({
  masterRecordId: z.string().uuid(),
  vendorCode: z.string(),
  legalName: z.string(),
  tradeName: z.string().nullable(),
  vendorCategory: z.string().nullable(),
  lifecycleStatus: VendorLifecycleStatusSchema,
  intakeSource: VendorIntakeSourceSchema,
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
  updatedAt: z.string(),
});
export type VendorProfileListRow = z.infer<typeof VendorProfileListRowSchema>;

export function parseVendorProfileListRow(row: Record<string, unknown>): VendorProfileListRow {
  return VendorProfileListRowSchema.parse({
    masterRecordId: row.master_record_id,
    vendorCode: row.vendor_code,
    legalName: row.legal_name,
    tradeName: row.trade_name ?? null,
    vendorCategory: row.vendor_category ?? null,
    lifecycleStatus: row.lifecycle_status,
    intakeSource: row.intake_source,
    recordVersion: row.record_version,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  });
}

export const VendorContactSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  name: z.string(),
  title: z.string().nullable(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  isPrimary: z.boolean(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type VendorContact = z.infer<typeof VendorContactSchema>;

/** email/phone are null when app.list_vendor_contacts masked them (caller lacks PRC:View personal data) -- this parser cannot itself distinguish "masked" from "never entered," matching app.vendor_rate_versions_directory's own cost_masked-flag precedent being the caller's responsibility to track separately if needed. */
export function parseVendorContact(row: Record<string, unknown>): VendorContact {
  return VendorContactSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    name: row.name,
    title: row.title ?? null,
    email: row.email ?? null,
    phone: row.phone ?? null,
    isPrimary: row.is_primary,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const VendorAddressSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  addressType: VendorAddressTypeSchema,
  street: z.string(),
  city: z.string(),
  province: z.string().nullable(),
  postalCode: z.string().nullable(),
  country: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type VendorAddress = z.infer<typeof VendorAddressSchema>;

export function parseVendorAddress(row: Record<string, unknown>): VendorAddress {
  return VendorAddressSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    addressType: row.address_type,
    street: row.street,
    city: row.city,
    province: row.province ?? null,
    postalCode: row.postal_code ?? null,
    country: row.country,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const VendorServiceSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  serviceType: z.string(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type VendorService = z.infer<typeof VendorServiceSchema>;

export function parseVendorService(row: Record<string, unknown>): VendorService {
  return VendorServiceSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    serviceType: row.service_type,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const VendorCoverageSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  originLane: z.string(),
  destinationLane: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type VendorCoverage = z.infer<typeof VendorCoverageSchema>;

export function parseVendorCoverage(row: Record<string, unknown>): VendorCoverage {
  return VendorCoverageSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    originLane: row.origin_lane,
    destinationLane: row.destination_lane ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const VendorDuplicateCandidateSchema = z.object({
  id: z.string().uuid(),
  sourceMasterRecordId: z.string().uuid(),
  candidateMasterRecordId: z.string().uuid(),
  similarityBasis: z.string(),
  similarityScore: z.coerce.number().nullable(),
  decision: VendorDuplicateDecisionSchema,
  decidedBy: z.string().nullable(),
  decidedAt: z.string().nullable(),
  decidedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
  createdAt: z.string(),
});
export type VendorDuplicateCandidate = z.infer<typeof VendorDuplicateCandidateSchema>;

export function parseVendorDuplicateCandidate(row: Record<string, unknown>): VendorDuplicateCandidate {
  return VendorDuplicateCandidateSchema.parse({
    id: row.id,
    sourceMasterRecordId: row.source_master_record_id,
    candidateMasterRecordId: row.candidate_master_record_id,
    similarityBasis: row.similarity_basis,
    similarityScore: row.similarity_score ?? null,
    decision: row.decision,
    decidedBy: row.decided_by ?? null,
    decidedAt: row.decided_at ?? null,
    decidedReason: row.decided_reason ?? null,
    recordVersion: row.record_version,
    createdAt: row.created_at,
  });
}

export const VendorDuplicateSearchRowSchema = z.object({
  masterRecordId: z.string().uuid(),
  vendorCode: z.string(),
  legalName: z.string(),
  tradeName: z.string().nullable(),
  similarityScore: z.coerce.number(),
});
export type VendorDuplicateSearchRow = z.infer<typeof VendorDuplicateSearchRowSchema>;

export function parseVendorDuplicateSearchRow(row: Record<string, unknown>): VendorDuplicateSearchRow {
  return VendorDuplicateSearchRowSchema.parse({
    masterRecordId: row.master_record_id,
    vendorCode: row.vendor_code,
    legalName: row.legal_name,
    tradeName: row.trade_name ?? null,
    similarityScore: row.similarity_score,
  });
}

export const VendorLifecycleEventSchema = z.object({
  id: z.string().uuid(),
  masterRecordId: z.string().uuid(),
  fromStatus: z.string(),
  toStatus: z.string(),
  reason: z.string().nullable(),
  evidenceRef: z.string().nullable(),
  actorLabel: z.string().nullable(),
  occurredAt: z.string(),
});
export type VendorLifecycleEvent = z.infer<typeof VendorLifecycleEventSchema>;

export function parseVendorLifecycleEvent(row: Record<string, unknown>): VendorLifecycleEvent {
  return VendorLifecycleEventSchema.parse({
    id: row.id,
    masterRecordId: row.master_record_id,
    fromStatus: row.from_status,
    toStatus: row.to_status,
    reason: row.reason ?? null,
    evidenceRef: row.evidence_ref ?? null,
    actorLabel: row.actor_label ?? null,
    occurredAt: row.occurred_at,
  });
}

/** app.create_vendor_intake_token's own return shape -- raw_token is present exactly once (a true first issuance), null on an idempotent replay. */
export const VendorIntakeTokenIssueResultSchema = z.object({
  tokenId: z.string().uuid(),
  rawToken: z.string().nullable(),
  expiresAt: z.string(),
  intendedEmail: z.string(),
});
export type VendorIntakeTokenIssueResult = z.infer<typeof VendorIntakeTokenIssueResultSchema>;

export function parseVendorIntakeTokenIssueResult(row: Record<string, unknown>): VendorIntakeTokenIssueResult {
  return VendorIntakeTokenIssueResultSchema.parse({
    tokenId: row.token_id,
    rawToken: row.raw_token ?? null,
    expiresAt: row.expires_at,
    intendedEmail: row.intended_email,
  });
}

export const VendorIntakeTokenSchema = z.object({
  id: z.string().uuid(),
  tenantId: z.string().uuid(),
  status: VendorIntakeTokenStatusSchema,
  intendedEmail: z.string(),
  expiresAt: z.string(),
  createdBy: z.string().nullable(),
  createdAt: z.string(),
  redeemedAt: z.string().nullable(),
  redeemedMasterRecordId: z.string().uuid().nullable(),
  revokedAt: z.string().nullable(),
  revokedReason: z.string().nullable(),
  recordVersion: z.number().int().positive(),
});
export type VendorIntakeToken = z.infer<typeof VendorIntakeTokenSchema>;

export function parseVendorIntakeToken(row: Record<string, unknown>): VendorIntakeToken {
  return VendorIntakeTokenSchema.parse({
    id: row.id,
    tenantId: row.tenant_id,
    status: row.status,
    intendedEmail: row.intended_email,
    expiresAt: row.expires_at,
    createdBy: row.created_by ?? null,
    createdAt: row.created_at,
    redeemedAt: row.redeemed_at ?? null,
    redeemedMasterRecordId: row.redeemed_master_record_id ?? null,
    revokedAt: row.revoked_at ?? null,
    revokedReason: row.revoked_reason ?? null,
    recordVersion: row.record_version,
  });
}

/** app.redeem_vendor_intake_token_and_submit / app.submit_vendor_profile_self_registration's own shared shape -- never raises, always returns a status column (design note 8). */
export const VendorIntakeSubmitResultSchema = z.object({
  submitStatus: z.enum(["ok", "not_found", "invalid", "rate_limited", "disabled", "conflict"]),
  masterRecordId: z.string().uuid().nullable(),
});
export type VendorIntakeSubmitResult = z.infer<typeof VendorIntakeSubmitResultSchema>;

export function parseVendorIntakeSubmitResult(row: Record<string, unknown>): VendorIntakeSubmitResult {
  return VendorIntakeSubmitResultSchema.parse({
    submitStatus: row.submit_status,
    masterRecordId: row.master_record_id ?? null,
  });
}

/** app.resolve_vendor_self_registration_target's own shape -- tenantId/enabled collapse uniformly to (null, false) for a nonexistent slug, an inactive tenant, AND a tenant that has not enabled self-registration, so the public page can never distinguish those three cases (no enumeration signal). */
export const VendorSelfRegistrationTargetSchema = z.object({
  tenantId: z.string().uuid().nullable(),
  selfRegistrationEnabled: z.boolean(),
});
export type VendorSelfRegistrationTarget = z.infer<typeof VendorSelfRegistrationTargetSchema>;

export function parseVendorSelfRegistrationTarget(row: Record<string, unknown>): VendorSelfRegistrationTarget {
  return VendorSelfRegistrationTargetSchema.parse({
    tenantId: row.tenant_id ?? null,
    selfRegistrationEnabled: row.self_registration_enabled,
  });
}

// --- Mutation input schemas ---

export const CreateVendorProfileDraftInputSchema = z.object({
  tenantId: z.string().uuid(),
  legalName: z.string().min(1),
  tradeName: z.string().nullable(),
  legalEntityType: z.string().nullable(),
  businessRegistrationNumber: z.string().nullable(),
  vendorCategory: z.string().nullable(),
  paymentTermDays: z.number().int().min(0).nullable(),
  intakeSource: z.enum(["staff_created", "bulk_import"]),
  idempotencyKey: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateVendorProfileDraftInput = z.input<typeof CreateVendorProfileDraftInputSchema>;

const RecordActionInputBase = {
  masterRecordId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
};

export const SubmitVendorProfileForReviewInputSchema = z.object(RecordActionInputBase);
export type SubmitVendorProfileForReviewInput = z.input<typeof SubmitVendorProfileForReviewInputSchema>;

export const BeginVendorProfileReviewInputSchema = z.object(RecordActionInputBase);
export type BeginVendorProfileReviewInput = z.input<typeof BeginVendorProfileReviewInputSchema>;

export const DecideVendorProfileReviewInputSchema = z.object({
  ...RecordActionInputBase,
  decision: VendorReviewDecisionSchema,
  reason: z.string().nullable(),
});
export type DecideVendorProfileReviewInput = z.input<typeof DecideVendorProfileReviewInputSchema>;

export const ActivateVendorProfileInputSchema = z.object(RecordActionInputBase);
export type ActivateVendorProfileInput = z.input<typeof ActivateVendorProfileInputSchema>;

export const SuspendVendorProfileInputSchema = z.object({ ...RecordActionInputBase, reason: z.string().min(1) });
export type SuspendVendorProfileInput = z.input<typeof SuspendVendorProfileInputSchema>;

export const ReactivateVendorProfileInputSchema = z.object(RecordActionInputBase);
export type ReactivateVendorProfileInput = z.input<typeof ReactivateVendorProfileInputSchema>;

export const ArchiveVendorProfileInputSchema = z.object({ ...RecordActionInputBase, reason: z.string().nullable() });
export type ArchiveVendorProfileInput = z.input<typeof ArchiveVendorProfileInputSchema>;

export const BlacklistVendorProfileInputSchema = z.object({
  ...RecordActionInputBase,
  reason: z.string().min(1),
  evidenceRef: z.string().min(1),
});
export type BlacklistVendorProfileInput = z.input<typeof BlacklistVendorProfileInputSchema>;

export const AddVendorContactInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  name: z.string().min(1),
  title: z.string().nullable(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  isPrimary: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddVendorContactInput = z.input<typeof AddVendorContactInputSchema>;

export const UpdateVendorContactInputSchema = z.object({
  contactId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  name: z.string().min(1),
  title: z.string().nullable(),
  email: z.string().nullable(),
  phone: z.string().nullable(),
  isPrimary: z.boolean(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateVendorContactInput = z.input<typeof UpdateVendorContactInputSchema>;

export const RemoveVendorContactInputSchema = z.object({
  contactId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveVendorContactInput = z.input<typeof RemoveVendorContactInputSchema>;

export const AddVendorAddressInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  addressType: VendorAddressTypeSchema,
  street: z.string().min(1),
  city: z.string().min(1),
  province: z.string().nullable(),
  postalCode: z.string().nullable(),
  country: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddVendorAddressInput = z.input<typeof AddVendorAddressInputSchema>;

export const UpdateVendorAddressInputSchema = z.object({
  addressId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  addressType: VendorAddressTypeSchema,
  street: z.string().min(1),
  city: z.string().min(1),
  province: z.string().nullable(),
  postalCode: z.string().nullable(),
  country: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateVendorAddressInput = z.input<typeof UpdateVendorAddressInputSchema>;

export const RemoveVendorAddressInputSchema = z.object({
  addressId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveVendorAddressInput = z.input<typeof RemoveVendorAddressInputSchema>;

export const AddVendorServiceInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  serviceType: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddVendorServiceInput = z.input<typeof AddVendorServiceInputSchema>;

export const UpdateVendorServiceInputSchema = z.object({
  serviceId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  serviceType: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateVendorServiceInput = z.input<typeof UpdateVendorServiceInputSchema>;

export const RemoveVendorServiceInputSchema = z.object({
  serviceId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveVendorServiceInput = z.input<typeof RemoveVendorServiceInputSchema>;

export const AddVendorCoverageInputSchema = z.object({
  masterRecordId: z.string().uuid(),
  originLane: z.string().min(1),
  destinationLane: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type AddVendorCoverageInput = z.input<typeof AddVendorCoverageInputSchema>;

export const UpdateVendorCoverageInputSchema = z.object({
  coverageId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  originLane: z.string().min(1),
  destinationLane: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type UpdateVendorCoverageInput = z.input<typeof UpdateVendorCoverageInputSchema>;

export const RemoveVendorCoverageInputSchema = z.object({
  coverageId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RemoveVendorCoverageInput = z.input<typeof RemoveVendorCoverageInputSchema>;

export const FlagVendorDuplicateCandidateInputSchema = z.object({
  sourceMasterRecordId: z.string().uuid(),
  candidateMasterRecordId: z.string().uuid(),
  similarityBasis: z.string().min(1),
  similarityScore: z.number().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type FlagVendorDuplicateCandidateInput = z.input<typeof FlagVendorDuplicateCandidateInputSchema>;

export const DecideVendorDuplicateCandidateInputSchema = z.object({
  candidateId: z.string().uuid(),
  expectedVersion: z.number().int().positive(),
  decision: z.enum(["linked", "dismissed"]),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type DecideVendorDuplicateCandidateInput = z.input<typeof DecideVendorDuplicateCandidateInputSchema>;

export const CreateVendorIntakeTokenInputSchema = z.object({
  tenantId: z.string().uuid(),
  intendedEmail: z.string().email(),
  validityDays: z.number().int().positive(),
  idempotencyKey: z.string().nullable(),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type CreateVendorIntakeTokenInput = z.input<typeof CreateVendorIntakeTokenInputSchema>;

export const RevokeVendorIntakeTokenInputSchema = z.object({
  tokenId: z.string().uuid(),
  reason: z.string().min(1),
  actorAuthUserId: z.string().uuid(),
  actorLabel: z.string(),
});
export type RevokeVendorIntakeTokenInput = z.input<typeof RevokeVendorIntakeTokenInputSchema>;

/** Genuinely anonymous -- no actorAuthUserId/actorLabel field exists, matching the RPC's own no-session shape (design note 8). */
export const RedeemVendorIntakeTokenInputSchema = z.object({
  rawToken: z.string().min(1),
  clientKey: z.string().min(1),
  legalName: z.string().min(1),
  tradeName: z.string().nullable(),
  legalEntityType: z.string().nullable(),
  businessRegistrationNumber: z.string().nullable(),
  vendorCategory: z.string().nullable(),
  paymentTermDays: z.number().int().min(0).nullable(),
  contactName: z.string().nullable(),
  contactEmail: z.string().nullable(),
  contactPhone: z.string().nullable(),
});
export type RedeemVendorIntakeTokenInput = z.input<typeof RedeemVendorIntakeTokenInputSchema>;

export const SubmitVendorProfileSelfRegistrationInputSchema = z.object({
  tenantId: z.string().uuid(),
  clientKey: z.string().min(1),
  legalName: z.string().min(1),
  tradeName: z.string().nullable(),
  legalEntityType: z.string().nullable(),
  businessRegistrationNumber: z.string().nullable(),
  vendorCategory: z.string().nullable(),
  paymentTermDays: z.number().int().min(0).nullable(),
  contactName: z.string().nullable(),
  contactEmail: z.string().nullable(),
  contactPhone: z.string().nullable(),
  idempotencyKey: z.string().nullable(),
});
export type SubmitVendorProfileSelfRegistrationInput = z.input<typeof SubmitVendorProfileSelfRegistrationInputSchema>;
