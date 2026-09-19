/**
 * Vendor Profile mutation primitives (PRC-251, CG-S11-PRC-002). Thin, typed wrappers
 * around every lifecycle/child-CRUD/duplicate-review/intake RPC in
 * supabase/migrations/20260730580000_create_procurement_vendor_registration.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorProfileDraftInputSchema,
  SubmitVendorProfileForReviewInputSchema,
  BeginVendorProfileReviewInputSchema,
  DecideVendorProfileReviewInputSchema,
  ActivateVendorProfileInputSchema,
  SuspendVendorProfileInputSchema,
  ReactivateVendorProfileInputSchema,
  ArchiveVendorProfileInputSchema,
  BlacklistVendorProfileInputSchema,
  AddVendorContactInputSchema,
  UpdateVendorContactInputSchema,
  RemoveVendorContactInputSchema,
  AddVendorAddressInputSchema,
  UpdateVendorAddressInputSchema,
  RemoveVendorAddressInputSchema,
  AddVendorServiceInputSchema,
  UpdateVendorServiceInputSchema,
  RemoveVendorServiceInputSchema,
  AddVendorCoverageInputSchema,
  UpdateVendorCoverageInputSchema,
  RemoveVendorCoverageInputSchema,
  FlagVendorDuplicateCandidateInputSchema,
  DecideVendorDuplicateCandidateInputSchema,
  CreateVendorIntakeTokenInputSchema,
  RevokeVendorIntakeTokenInputSchema,
  RedeemVendorIntakeTokenInputSchema,
  SubmitVendorProfileSelfRegistrationInputSchema,
  parseVendorSelfRegistrationTarget,
  parseVendorProfileMutationResult,
  parseVendorContact,
  parseVendorAddress,
  parseVendorService,
  parseVendorCoverage,
  parseVendorDuplicateCandidate,
  parseVendorIntakeTokenIssueResult,
  parseVendorIntakeToken,
  parseVendorIntakeSubmitResult,
  type CreateVendorProfileDraftInput,
  type SubmitVendorProfileForReviewInput,
  type BeginVendorProfileReviewInput,
  type DecideVendorProfileReviewInput,
  type ActivateVendorProfileInput,
  type SuspendVendorProfileInput,
  type ReactivateVendorProfileInput,
  type ArchiveVendorProfileInput,
  type BlacklistVendorProfileInput,
  type AddVendorContactInput,
  type UpdateVendorContactInput,
  type RemoveVendorContactInput,
  type AddVendorAddressInput,
  type UpdateVendorAddressInput,
  type RemoveVendorAddressInput,
  type AddVendorServiceInput,
  type UpdateVendorServiceInput,
  type RemoveVendorServiceInput,
  type AddVendorCoverageInput,
  type UpdateVendorCoverageInput,
  type RemoveVendorCoverageInput,
  type FlagVendorDuplicateCandidateInput,
  type DecideVendorDuplicateCandidateInput,
  type CreateVendorIntakeTokenInput,
  type RevokeVendorIntakeTokenInput,
  type RedeemVendorIntakeTokenInput,
  type SubmitVendorProfileSelfRegistrationInput,
  type VendorProfileMutationResult,
  type VendorContact,
  type VendorAddress,
  type VendorService,
  type VendorCoverage,
  type VendorDuplicateCandidate,
  type VendorIntakeTokenIssueResult,
  type VendorIntakeToken,
  type VendorIntakeSubmitResult,
  type VendorSelfRegistrationTarget,
} from "../contracts/vendor-profile/vendor-profile.ts";
import {
  ValidateStagingRowInputSchema,
  CommitVendorImportJobInputSchema,
  parseImportStagingRow,
  parseImportExportJob,
  type ValidateStagingRowInput,
  type CommitVendorImportJobInput,
  type ImportStagingRow,
  type ImportExportJob,
} from "../contracts/import-export/import-export.ts";

export type VendorProfileMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_PROFILE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "invalid_legal_name",
  "invalid_intake_source",
  "invalid_payment_term",
  "idempotency_key_conflict",
  "vendor_profile_not_found",
  "stale_version",
  "invalid_transition",
  "missing_required_contact",
  "missing_required_address",
  "missing_required_service",
  "unresolved_duplicate_candidates",
  "invalid_decision",
  "reason_required",
  "evidence_required",
  "vendor_profile_not_draft",
  "invalid_contact",
  "contact_not_found",
  "invalid_address_type",
  "invalid_address",
  "address_not_found",
  "invalid_service",
  "service_not_found",
  "duplicate_service",
  "invalid_coverage",
  "coverage_not_found",
  "invalid_candidate",
  "candidate_not_found",
  "invalid_email",
  "invalid_validity",
  "token_not_found",
  "invalid_response",
  // --- Staged import (CG-AUDIT-2026-09-02 A4, third import schema) ---
  // app.validate_vendor_import_row/app.commit_vendor_import_job
  // (supabase/migrations/20260830100000_create_vendor_import_adapter.sql,
  // latest redefinition 20260903122000) compose the generic PLT-131
  // framework's own errors plus these domain-specific ones.
  "import_export_job_not_found",
  "import_export_wrong_schema",
  "job_actor_unauthorized",
  "import_export_job_not_committable",
  "import_export_job_not_fully_validated",
  "import_export_job_has_invalid_rows",
  "import_vendor_profile_already_bound",
  "mfa_step_up_required",
  "ip_not_allowed",
] as const;
type KnownVendorProfileMutationErrorCode = (typeof VENDOR_PROFILE_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorProfileMutationErrorCode = KnownVendorProfileMutationErrorCode | "mutation_failed";

export class VendorProfileMutationError extends Error {
  readonly code: VendorProfileMutationErrorCode;

  constructor(code: VendorProfileMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorProfileMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorProfileMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_PROFILE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorProfileMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseProfileResponse(data: unknown, rpcName: string): VendorProfileMutationResult {
  const row = firstRow(data);
  if (!row) {
    throw new VendorProfileMutationError("invalid_response", `${rpcName} returned no row`);
  }
  return parseVendorProfileMutationResult(row);
}

// --- Lifecycle ---

export async function createVendorProfileDraft(client: VendorProfileMutationRpcClient, input: CreateVendorProfileDraftInput): Promise<VendorProfileMutationResult> {
  const parsed = CreateVendorProfileDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_profile_draft", {
    p_tenant_id: parsed.tenantId,
    p_legal_name: parsed.legalName,
    p_trade_name: parsed.tradeName,
    p_legal_entity_type: parsed.legalEntityType,
    p_business_registration_number: parsed.businessRegistrationNumber,
    p_vendor_category: parsed.vendorCategory,
    p_payment_term_days: parsed.paymentTermDays,
    p_intake_source: parsed.intakeSource,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "create_vendor_profile_draft");
}

export async function submitVendorProfileForReview(client: VendorProfileMutationRpcClient, input: SubmitVendorProfileForReviewInput): Promise<VendorProfileMutationResult> {
  const parsed = SubmitVendorProfileForReviewInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_vendor_profile_for_review", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "submit_vendor_profile_for_review");
}

export async function beginVendorProfileReview(client: VendorProfileMutationRpcClient, input: BeginVendorProfileReviewInput): Promise<VendorProfileMutationResult> {
  const parsed = BeginVendorProfileReviewInputSchema.parse(input);
  const { data, error } = await client.rpc("begin_vendor_profile_review", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "begin_vendor_profile_review");
}

export async function decideVendorProfileReview(client: VendorProfileMutationRpcClient, input: DecideVendorProfileReviewInput): Promise<VendorProfileMutationResult> {
  const parsed = DecideVendorProfileReviewInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_profile_review", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "decide_vendor_profile_review");
}

export async function activateVendorProfile(client: VendorProfileMutationRpcClient, input: ActivateVendorProfileInput): Promise<VendorProfileMutationResult> {
  const parsed = ActivateVendorProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("activate_vendor_profile", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "activate_vendor_profile");
}

export async function suspendVendorProfile(client: VendorProfileMutationRpcClient, input: SuspendVendorProfileInput): Promise<VendorProfileMutationResult> {
  const parsed = SuspendVendorProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("suspend_vendor_profile", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "suspend_vendor_profile");
}

export async function reactivateVendorProfile(client: VendorProfileMutationRpcClient, input: ReactivateVendorProfileInput): Promise<VendorProfileMutationResult> {
  const parsed = ReactivateVendorProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("reactivate_vendor_profile", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "reactivate_vendor_profile");
}

export async function archiveVendorProfile(client: VendorProfileMutationRpcClient, input: ArchiveVendorProfileInput): Promise<VendorProfileMutationResult> {
  const parsed = ArchiveVendorProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("archive_vendor_profile", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "archive_vendor_profile");
}

export async function blacklistVendorProfile(client: VendorProfileMutationRpcClient, input: BlacklistVendorProfileInput): Promise<VendorProfileMutationResult> {
  const parsed = BlacklistVendorProfileInputSchema.parse(input);
  const { data, error } = await client.rpc("blacklist_vendor_profile", {
    p_master_record_id: parsed.masterRecordId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_evidence_ref: parsed.evidenceRef,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  return parseProfileResponse(data, "blacklist_vendor_profile");
}

// --- Child-record CRUD (draft-only) ---

export async function addVendorContact(client: VendorProfileMutationRpcClient, input: AddVendorContactInput): Promise<VendorContact> {
  const parsed = AddVendorContactInputSchema.parse(input);
  const { data, error } = await client.rpc("add_vendor_contact", {
    p_master_record_id: parsed.masterRecordId,
    p_name: parsed.name,
    p_title: parsed.title,
    p_email: parsed.email,
    p_phone: parsed.phone,
    p_is_primary: parsed.isPrimary,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "add_vendor_contact returned no row");
  return parseVendorContact(row);
}

export async function updateVendorContact(client: VendorProfileMutationRpcClient, input: UpdateVendorContactInput): Promise<VendorContact> {
  const parsed = UpdateVendorContactInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_contact", {
    p_contact_id: parsed.contactId,
    p_expected_version: parsed.expectedVersion,
    p_name: parsed.name,
    p_title: parsed.title,
    p_email: parsed.email,
    p_phone: parsed.phone,
    p_is_primary: parsed.isPrimary,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "update_vendor_contact returned no row");
  return parseVendorContact(row);
}

export async function removeVendorContact(client: VendorProfileMutationRpcClient, input: RemoveVendorContactInput): Promise<VendorContact> {
  const parsed = RemoveVendorContactInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_vendor_contact", {
    p_contact_id: parsed.contactId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "remove_vendor_contact returned no row");
  return parseVendorContact(row);
}

export async function addVendorAddress(client: VendorProfileMutationRpcClient, input: AddVendorAddressInput): Promise<VendorAddress> {
  const parsed = AddVendorAddressInputSchema.parse(input);
  const { data, error } = await client.rpc("add_vendor_address", {
    p_master_record_id: parsed.masterRecordId,
    p_address_type: parsed.addressType,
    p_street: parsed.street,
    p_city: parsed.city,
    p_province: parsed.province,
    p_postal_code: parsed.postalCode,
    p_country: parsed.country,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "add_vendor_address returned no row");
  return parseVendorAddress(row);
}

export async function updateVendorAddress(client: VendorProfileMutationRpcClient, input: UpdateVendorAddressInput): Promise<VendorAddress> {
  const parsed = UpdateVendorAddressInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_address", {
    p_address_id: parsed.addressId,
    p_expected_version: parsed.expectedVersion,
    p_address_type: parsed.addressType,
    p_street: parsed.street,
    p_city: parsed.city,
    p_province: parsed.province,
    p_postal_code: parsed.postalCode,
    p_country: parsed.country,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "update_vendor_address returned no row");
  return parseVendorAddress(row);
}

export async function removeVendorAddress(client: VendorProfileMutationRpcClient, input: RemoveVendorAddressInput): Promise<VendorAddress> {
  const parsed = RemoveVendorAddressInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_vendor_address", {
    p_address_id: parsed.addressId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "remove_vendor_address returned no row");
  return parseVendorAddress(row);
}

export async function addVendorService(client: VendorProfileMutationRpcClient, input: AddVendorServiceInput): Promise<VendorService> {
  const parsed = AddVendorServiceInputSchema.parse(input);
  const { data, error } = await client.rpc("add_vendor_service", {
    p_master_record_id: parsed.masterRecordId,
    p_service_type: parsed.serviceType,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "add_vendor_service returned no row");
  return parseVendorService(row);
}

export async function updateVendorService(client: VendorProfileMutationRpcClient, input: UpdateVendorServiceInput): Promise<VendorService> {
  const parsed = UpdateVendorServiceInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_service", {
    p_service_id: parsed.serviceId,
    p_expected_version: parsed.expectedVersion,
    p_service_type: parsed.serviceType,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "update_vendor_service returned no row");
  return parseVendorService(row);
}

export async function removeVendorService(client: VendorProfileMutationRpcClient, input: RemoveVendorServiceInput): Promise<VendorService> {
  const parsed = RemoveVendorServiceInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_vendor_service", {
    p_service_id: parsed.serviceId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "remove_vendor_service returned no row");
  return parseVendorService(row);
}

export async function addVendorCoverage(client: VendorProfileMutationRpcClient, input: AddVendorCoverageInput): Promise<VendorCoverage> {
  const parsed = AddVendorCoverageInputSchema.parse(input);
  const { data, error } = await client.rpc("add_vendor_coverage", {
    p_master_record_id: parsed.masterRecordId,
    p_origin_lane: parsed.originLane,
    p_destination_lane: parsed.destinationLane,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "add_vendor_coverage returned no row");
  return parseVendorCoverage(row);
}

export async function updateVendorCoverage(client: VendorProfileMutationRpcClient, input: UpdateVendorCoverageInput): Promise<VendorCoverage> {
  const parsed = UpdateVendorCoverageInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_coverage", {
    p_coverage_id: parsed.coverageId,
    p_expected_version: parsed.expectedVersion,
    p_origin_lane: parsed.originLane,
    p_destination_lane: parsed.destinationLane,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "update_vendor_coverage returned no row");
  return parseVendorCoverage(row);
}

export async function removeVendorCoverage(client: VendorProfileMutationRpcClient, input: RemoveVendorCoverageInput): Promise<VendorCoverage> {
  const parsed = RemoveVendorCoverageInputSchema.parse(input);
  const { data, error } = await client.rpc("remove_vendor_coverage", {
    p_coverage_id: parsed.coverageId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "remove_vendor_coverage returned no row");
  return parseVendorCoverage(row);
}

// --- Duplicate review (never auto-merges) ---

export async function flagVendorDuplicateCandidate(client: VendorProfileMutationRpcClient, input: FlagVendorDuplicateCandidateInput): Promise<VendorDuplicateCandidate> {
  const parsed = FlagVendorDuplicateCandidateInputSchema.parse(input);
  const { data, error } = await client.rpc("flag_vendor_duplicate_candidate", {
    p_source_master_record_id: parsed.sourceMasterRecordId,
    p_candidate_master_record_id: parsed.candidateMasterRecordId,
    p_similarity_basis: parsed.similarityBasis,
    p_similarity_score: parsed.similarityScore,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "flag_vendor_duplicate_candidate returned no row");
  return parseVendorDuplicateCandidate(row);
}

export async function decideVendorDuplicateCandidate(client: VendorProfileMutationRpcClient, input: DecideVendorDuplicateCandidateInput): Promise<VendorDuplicateCandidate> {
  const parsed = DecideVendorDuplicateCandidateInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_duplicate_candidate", {
    p_candidate_id: parsed.candidateId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "decide_vendor_duplicate_candidate returned no row");
  return parseVendorDuplicateCandidate(row);
}

// --- Intake (staff-facing) ---

export async function createVendorIntakeToken(client: VendorProfileMutationRpcClient, input: CreateVendorIntakeTokenInput): Promise<VendorIntakeTokenIssueResult> {
  const parsed = CreateVendorIntakeTokenInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_intake_token", {
    p_tenant_id: parsed.tenantId,
    p_intended_email: parsed.intendedEmail,
    p_validity_days: parsed.validityDays,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "create_vendor_intake_token returned no row");
  return parseVendorIntakeTokenIssueResult(row);
}

export async function revokeVendorIntakeToken(client: VendorProfileMutationRpcClient, input: RevokeVendorIntakeTokenInput): Promise<VendorIntakeToken> {
  const parsed = RevokeVendorIntakeTokenInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_vendor_intake_token", {
    p_token_id: parsed.tokenId,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "revoke_vendor_intake_token returned no row");
  return parseVendorIntakeToken(row);
}

// --- Anonymous intake entry points (design note 8: no actor/session parameter) ---

/** Calls app.redeem_vendor_intake_token_and_submit -- genuinely anonymous, never raises (returns a status column instead). The caller MUST use a service-role client (never a browser-side anon client); see server/actions or app/(public)/vendor-intake/[token]/actions.ts. */
export async function redeemVendorIntakeToken(client: VendorProfileMutationRpcClient, input: RedeemVendorIntakeTokenInput): Promise<VendorIntakeSubmitResult> {
  const parsed = RedeemVendorIntakeTokenInputSchema.parse(input);
  const { data, error } = await client.rpc("redeem_vendor_intake_token_and_submit", {
    p_raw_token: parsed.rawToken,
    p_client_key: parsed.clientKey,
    p_legal_name: parsed.legalName,
    p_trade_name: parsed.tradeName,
    p_legal_entity_type: parsed.legalEntityType,
    p_business_registration_number: parsed.businessRegistrationNumber,
    p_vendor_category: parsed.vendorCategory,
    p_payment_term_days: parsed.paymentTermDays,
    p_contact_name: parsed.contactName,
    p_contact_email: parsed.contactEmail,
    p_contact_phone: parsed.contactPhone,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "redeem_vendor_intake_token_and_submit returned no row");
  return parseVendorIntakeSubmitResult(row);
}

/** Calls app.submit_vendor_profile_self_registration -- genuinely anonymous, gated only by the tenant's own published procurement.vendor_self_registration.enabled config flag. Same service-role-client requirement as redeemVendorIntakeToken above. */
export async function submitVendorProfileSelfRegistration(client: VendorProfileMutationRpcClient, input: SubmitVendorProfileSelfRegistrationInput): Promise<VendorIntakeSubmitResult> {
  const parsed = SubmitVendorProfileSelfRegistrationInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_vendor_profile_self_registration", {
    p_tenant_id: parsed.tenantId,
    p_client_key: parsed.clientKey,
    p_legal_name: parsed.legalName,
    p_trade_name: parsed.tradeName,
    p_legal_entity_type: parsed.legalEntityType,
    p_business_registration_number: parsed.businessRegistrationNumber,
    p_vendor_category: parsed.vendorCategory,
    p_payment_term_days: parsed.paymentTermDays,
    p_contact_name: parsed.contactName,
    p_contact_email: parsed.contactEmail,
    p_contact_phone: parsed.contactPhone,
    p_idempotency_key: parsed.idempotencyKey,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "submit_vendor_profile_self_registration returned no row");
  return parseVendorIntakeSubmitResult(row);
}

/**
 * Calls app.resolve_vendor_self_registration_target -- genuinely anonymous, the one
 * slug->tenant_id resolution path for the public self-registration page
 * (app/(public)/vendor-intake/register/[tenantSlug]/). Never throws on a
 * nonexistent/inactive/self-registration-disabled tenant -- it returns
 * `{ tenantId: null, selfRegistrationEnabled: false }` uniformly for all three, by
 * design (no enumeration signal). Same service-role-client requirement as every
 * other anonymous entry point in this module.
 */
export async function resolveVendorSelfRegistrationTarget(client: VendorProfileMutationRpcClient, tenantSlug: string): Promise<VendorSelfRegistrationTarget> {
  const { data, error } = await client.rpc("resolve_vendor_self_registration_target", { p_tenant_slug: tenantSlug });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorProfileMutationError("invalid_response", "resolve_vendor_self_registration_target returned no row");
  return parseVendorSelfRegistrationTarget(row);
}

// --- Staged import (CG-AUDIT-2026-09-02 A4, third import schema) ---
// app.validate_vendor_import_row returns app.import_staging_rows and
// app.commit_vendor_import_job returns app.jobs -- the SAME composite types the
// generic PLT-131 app.validate_staging_row/app.commit_import_job return, so both
// reuse the generic parsers directly, mirroring
// server/mutations/finance-opening-balance-import.ts's own precedent (never
// server/mutations/employee.ts's own raw Record<string, unknown> return, which
// predates that reusable-parser convention).

/** Calls app.validate_staging_row UNCHANGED first, then adds formula/spreadsheet-injection rejection (legal_name, trade_name, legal_entity_type, business_registration_number, vendor_category), whitespace-only legal_name, and payment_term_days shape -- and refuses a row that supplies intake_source or any lifecycle/approval/blacklist field (those are never importable). */
export async function validateVendorImportRow(client: VendorProfileMutationRpcClient, input: ValidateStagingRowInput): Promise<ImportStagingRow> {
  const parsed = ValidateStagingRowInputSchema.parse(input);
  const { data, error } = await client.rpc("validate_vendor_import_row", {
    p_staging_row_id: parsed.stagingRowId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  if (!data || typeof data !== "object") throw new VendorProfileMutationError("invalid_response", "validate_vendor_import_row returned no row");
  return parseImportStagingRow(data as Record<string, unknown>);
}

/** Requires PRC:Import AND is_support_grant_authority (additive, never either-or). Writes only through app.create_vendor_profile_draft (never a direct INSERT), forcing intake_source='bulk_import' and stamping source_import_staging_row_id. Runs duplicate-candidate sweeps (trigram legal-name match, exact business_registration_number match) that FLAG for human review, never block the commit. */
export async function commitVendorImportJob(client: VendorProfileMutationRpcClient, input: CommitVendorImportJobInput): Promise<ImportExportJob> {
  const parsed = CommitVendorImportJobInputSchema.parse(input);
  const { data, error } = await client.rpc("commit_vendor_import_job", {
    p_job_id: parsed.jobId,
    p_allow_partial: parsed.allowPartial,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_client_ip: parsed.clientIp,
  });
  if (error) throw new VendorProfileMutationError(classifyError(error.message), error.message);
  if (!data || typeof data !== "object") throw new VendorProfileMutationError("invalid_response", "commit_vendor_import_job returned no row");
  return parseImportExportJob(data as Record<string, unknown>);
}
