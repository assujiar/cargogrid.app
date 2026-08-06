/**
 * Vendor Compliance mutation primitives (PRC-253, CG-S11-PRC-004). Thin, typed
 * wrappers around every requirement-lifecycle/document-lifecycle/waiver/
 * recalculation RPC in
 * supabase/migrations/20260730600000_create_procurement_vendor_compliance.sql.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  CreateVendorComplianceRequirementDraftInputSchema,
  UpdateVendorComplianceRequirementDraftInputSchema,
  PublishVendorComplianceRequirementInputSchema,
  ArchiveVendorComplianceRequirementInputSchema,
  SubmitVendorComplianceDocumentInputSchema,
  RenewVendorComplianceDocumentInputSchema,
  DecideVendorComplianceDocumentInputSchema,
  RequestVendorComplianceWaiverInputSchema,
  DecideVendorComplianceWaiverInputSchema,
  RevokeVendorComplianceWaiverInputSchema,
  ExpireVendorComplianceWaiversInputSchema,
  RecalculateVendorComplianceStatusInputSchema,
  RecalculateTenantVendorComplianceStatusInputSchema,
  AccessVendorComplianceDocumentEvidenceInputSchema,
  parseVendorComplianceRequirement,
  parseVendorComplianceDocument,
  parseVendorComplianceWaiver,
  parseVendorComplianceStatusRow,
  parseVendorComplianceDocumentEvidenceAccess,
  type CreateVendorComplianceRequirementDraftInput,
  type UpdateVendorComplianceRequirementDraftInput,
  type PublishVendorComplianceRequirementInput,
  type ArchiveVendorComplianceRequirementInput,
  type SubmitVendorComplianceDocumentInput,
  type RenewVendorComplianceDocumentInput,
  type DecideVendorComplianceDocumentInput,
  type RequestVendorComplianceWaiverInput,
  type DecideVendorComplianceWaiverInput,
  type RevokeVendorComplianceWaiverInput,
  type ExpireVendorComplianceWaiversInput,
  type RecalculateVendorComplianceStatusInput,
  type RecalculateTenantVendorComplianceStatusInput,
  type AccessVendorComplianceDocumentEvidenceInput,
  type VendorComplianceRequirement,
  type VendorComplianceDocument,
  type VendorComplianceWaiver,
  type VendorComplianceStatusRow,
  type VendorComplianceSweepResult,
  type VendorComplianceDocumentEvidenceAccess,
} from "../contracts/vendor-compliance/vendor-compliance.ts";

export type VendorComplianceMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_COMPLIANCE_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "insufficient_privilege",
  "invalid_name",
  "invalid_blocking_effect",
  "invalid_reminder_offset",
  "document_type_not_registered",
  "idempotency_key_conflict",
  "vendor_compliance_requirement_not_found",
  "vendor_compliance_requirement_not_draft",
  "stale_version",
  "invalid_transition",
  "superseded_requirement_not_found",
  "invalid_supersede",
  "active_requirement_exists",
  "reason_required",
  "vendor_profile_not_found",
  "requirement_not_published",
  "requirement_not_applicable",
  "inconsistent_issue_expiry_date",
  "expiry_date_required",
  "expiry_date_not_applicable",
  "evidence_file_not_found",
  "compliance_evidence_file_mismatch",
  "compliance_unsafe_evidence",
  "active_submission_exists",
  "vendor_compliance_document_not_found",
  "vendor_compliance_document_not_latest",
  "expiry_required_for_verification",
  "invalid_decision",
  "vendor_compliance_waiver_not_found",
  "invalid_validity_window",
  "self_approval_not_allowed",
  "tenant_required",
  "invalid_status_filter",
  "invalid_access_type",
  "file_actor_unauthorized",
  "document_file_not_found",
  "invalid_response",
] as const;
type KnownVendorComplianceMutationErrorCode = (typeof VENDOR_COMPLIANCE_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorComplianceMutationErrorCode = KnownVendorComplianceMutationErrorCode | "mutation_failed";

export class VendorComplianceMutationError extends Error {
  readonly code: VendorComplianceMutationErrorCode;

  constructor(code: VendorComplianceMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorComplianceMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorComplianceMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_COMPLIANCE_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorComplianceMutationErrorCode) : "mutation_failed";
}

function firstRow(data: unknown): Record<string, unknown> | null {
  const row = Array.isArray(data) ? data[0] : data;
  return row && typeof row === "object" ? (row as Record<string, unknown>) : null;
}

function parseRequirementResponse(data: unknown, rpcName: string): VendorComplianceRequirement {
  const row = firstRow(data);
  if (!row) throw new VendorComplianceMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorComplianceRequirement(row);
}

function parseDocumentResponse(data: unknown, rpcName: string): VendorComplianceDocument {
  const row = firstRow(data);
  if (!row) throw new VendorComplianceMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorComplianceDocument(row);
}

function parseWaiverResponse(data: unknown, rpcName: string): VendorComplianceWaiver {
  const row = firstRow(data);
  if (!row) throw new VendorComplianceMutationError("invalid_response", `${rpcName} returned no row`);
  return parseVendorComplianceWaiver(row);
}

function parseSweepResponse(data: unknown, rpcName: string, countKey: string): VendorComplianceSweepResult {
  const row = firstRow(data);
  if (!row) throw new VendorComplianceMutationError("invalid_response", `${rpcName} returned no row`);
  return { count: Number(row[countKey] ?? 0), moreRemaining: Boolean(row.more_remaining) };
}

// --- Requirement lifecycle ---

export async function createVendorComplianceRequirementDraft(
  client: VendorComplianceMutationRpcClient,
  input: CreateVendorComplianceRequirementDraftInput,
): Promise<VendorComplianceRequirement> {
  const parsed = CreateVendorComplianceRequirementDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_compliance_requirement_draft", {
    p_tenant_id: parsed.tenantId,
    p_vendor_category: parsed.vendorCategory ?? null,
    p_service_type: parsed.serviceType ?? null,
    p_document_type_code: parsed.documentTypeCode,
    p_name: parsed.name,
    p_description: parsed.description ?? null,
    p_blocking_effect: parsed.blockingEffect ?? null,
    p_requires_expiry: parsed.requiresExpiry ?? null,
    p_reminder_offsets: parsed.reminderOffsets ?? null,
    p_effective_from: parsed.effectiveFrom ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseRequirementResponse(data, "create_vendor_compliance_requirement_draft");
}

export async function updateVendorComplianceRequirementDraft(
  client: VendorComplianceMutationRpcClient,
  input: UpdateVendorComplianceRequirementDraftInput,
): Promise<VendorComplianceRequirement> {
  const parsed = UpdateVendorComplianceRequirementDraftInputSchema.parse(input);
  const { data, error } = await client.rpc("update_vendor_compliance_requirement_draft", {
    p_requirement_version_id: parsed.requirementVersionId,
    p_expected_version: parsed.expectedVersion,
    p_vendor_category: parsed.vendorCategory ?? null,
    p_service_type: parsed.serviceType ?? null,
    p_document_type_code: parsed.documentTypeCode,
    p_name: parsed.name,
    p_description: parsed.description ?? null,
    p_blocking_effect: parsed.blockingEffect ?? null,
    p_requires_expiry: parsed.requiresExpiry ?? null,
    p_reminder_offsets: parsed.reminderOffsets ?? null,
    p_effective_from: parsed.effectiveFrom ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseRequirementResponse(data, "update_vendor_compliance_requirement_draft");
}

export async function publishVendorComplianceRequirement(client: VendorComplianceMutationRpcClient, input: PublishVendorComplianceRequirementInput): Promise<VendorComplianceRequirement> {
  const parsed = PublishVendorComplianceRequirementInputSchema.parse(input);
  const { data, error } = await client.rpc("publish_vendor_compliance_requirement", {
    p_requirement_version_id: parsed.requirementVersionId,
    p_expected_version: parsed.expectedVersion,
    p_supersedes_version_id: parsed.supersedesVersionId ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseRequirementResponse(data, "publish_vendor_compliance_requirement");
}

export async function archiveVendorComplianceRequirement(client: VendorComplianceMutationRpcClient, input: ArchiveVendorComplianceRequirementInput): Promise<VendorComplianceRequirement> {
  const parsed = ArchiveVendorComplianceRequirementInputSchema.parse(input);
  const { data, error } = await client.rpc("archive_vendor_compliance_requirement", {
    p_requirement_version_id: parsed.requirementVersionId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseRequirementResponse(data, "archive_vendor_compliance_requirement");
}

// --- Document lifecycle ---

export async function submitVendorComplianceDocument(client: VendorComplianceMutationRpcClient, input: SubmitVendorComplianceDocumentInput): Promise<VendorComplianceDocument> {
  const parsed = SubmitVendorComplianceDocumentInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_vendor_compliance_document", {
    p_vendor_master_record_id: parsed.vendorMasterRecordId,
    p_requirement_version_id: parsed.requirementVersionId,
    p_file_id: parsed.fileId,
    p_issue_date: parsed.issueDate ?? null,
    p_expiry_date: parsed.expiryDate ?? null,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseDocumentResponse(data, "submit_vendor_compliance_document");
}

export async function renewVendorComplianceDocument(client: VendorComplianceMutationRpcClient, input: RenewVendorComplianceDocumentInput): Promise<VendorComplianceDocument> {
  const parsed = RenewVendorComplianceDocumentInputSchema.parse(input);
  const { data, error } = await client.rpc("renew_vendor_compliance_document", {
    p_previous_document_id: parsed.previousDocumentId,
    p_file_id: parsed.fileId,
    p_issue_date: parsed.issueDate ?? null,
    p_expiry_date: parsed.expiryDate ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseDocumentResponse(data, "renew_vendor_compliance_document");
}

export async function decideVendorComplianceDocument(client: VendorComplianceMutationRpcClient, input: DecideVendorComplianceDocumentInput): Promise<VendorComplianceDocument> {
  const parsed = DecideVendorComplianceDocumentInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_compliance_document", {
    p_document_id: parsed.documentId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_rejection_reason: parsed.rejectionReason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseDocumentResponse(data, "decide_vendor_compliance_document");
}

/**
 * Fix-pass addition (HIGH-severity finding, adversarial review): the document/
 * version viewer's own gated evidence-access call. Composes PRC:Download authority
 * with PLT-128's own app.authorize_file_access (malware-scan + record/sensitivity
 * gate, RPD-032) -- never a second, parallel check. A denied result is returned, not
 * thrown, with every file-identifying field nulled out (accessResult='denied',
 * accessReason set) so a caller can render "access denied: <reason>" inline.
 */
export async function accessVendorComplianceDocumentEvidence(
  client: VendorComplianceMutationRpcClient,
  input: AccessVendorComplianceDocumentEvidenceInput,
): Promise<VendorComplianceDocumentEvidenceAccess> {
  const parsed = AccessVendorComplianceDocumentEvidenceInputSchema.parse(input);
  const { data, error } = await client.rpc("access_vendor_compliance_document_evidence", {
    p_document_id: parsed.documentId,
    p_access_type: parsed.accessType,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_correlation_id: parsed.correlationId ?? null,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  const row = firstRow(data);
  if (!row) throw new VendorComplianceMutationError("invalid_response", "access_vendor_compliance_document_evidence returned no row");
  return parseVendorComplianceDocumentEvidenceAccess(row);
}

// --- Waivers ---

export async function requestVendorComplianceWaiver(client: VendorComplianceMutationRpcClient, input: RequestVendorComplianceWaiverInput): Promise<VendorComplianceWaiver> {
  const parsed = RequestVendorComplianceWaiverInputSchema.parse(input);
  const { data, error } = await client.rpc("request_vendor_compliance_waiver", {
    p_requirement_version_id: parsed.requirementVersionId,
    p_vendor_master_record_id: parsed.vendorMasterRecordId,
    p_reason: parsed.reason,
    p_valid_from: parsed.validFrom,
    p_valid_until: parsed.validUntil,
    p_idempotency_key: parsed.idempotencyKey ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseWaiverResponse(data, "request_vendor_compliance_waiver");
}

export async function decideVendorComplianceWaiver(client: VendorComplianceMutationRpcClient, input: DecideVendorComplianceWaiverInput): Promise<VendorComplianceWaiver> {
  const parsed = DecideVendorComplianceWaiverInputSchema.parse(input);
  const { data, error } = await client.rpc("decide_vendor_compliance_waiver", {
    p_waiver_id: parsed.waiverId,
    p_expected_version: parsed.expectedVersion,
    p_decision: parsed.decision,
    p_decision_reason: parsed.decisionReason ?? null,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseWaiverResponse(data, "decide_vendor_compliance_waiver");
}

export async function revokeVendorComplianceWaiver(client: VendorComplianceMutationRpcClient, input: RevokeVendorComplianceWaiverInput): Promise<VendorComplianceWaiver> {
  const parsed = RevokeVendorComplianceWaiverInputSchema.parse(input);
  const { data, error } = await client.rpc("revoke_vendor_compliance_waiver", {
    p_waiver_id: parsed.waiverId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseWaiverResponse(data, "revoke_vendor_compliance_waiver");
}

/** Bounded, PRC:Override-gated cosmetic sweep -- flips status to expired past valid_until. Eligibility-hold correctness never depends on this having run. */
export async function expireVendorComplianceWaivers(client: VendorComplianceMutationRpcClient, input: ExpireVendorComplianceWaiversInput): Promise<VendorComplianceSweepResult> {
  const parsed = ExpireVendorComplianceWaiversInputSchema.parse(input);
  const { data, error } = await client.rpc("expire_vendor_compliance_waivers", {
    p_tenant_id: parsed.tenantId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_max_rows: parsed.maxRows ?? null,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseSweepResponse(data, "expire_vendor_compliance_waivers", "expired_count");
}

// --- Status recalculation ---

/** Real, callable, bounded per-vendor recalculation (PRC:Edit-gated) -- not auto-scheduled (ISS-2026-015). Recomputes every applicable-or-previously-tracked requirement family for this vendor. */
export async function recalculateVendorComplianceStatus(client: VendorComplianceMutationRpcClient, input: RecalculateVendorComplianceStatusInput): Promise<VendorComplianceStatusRow[]> {
  const parsed = RecalculateVendorComplianceStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("recalculate_vendor_compliance_status", {
    p_vendor_master_record_id: parsed.vendorMasterRecordId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return ((data as Record<string, unknown>[] | null) ?? []).map(parseVendorComplianceStatusRow);
}

/** Bounded, PRC:Override-gated tenant-wide sweep, mirroring app.purge_tracking_telemetry_history's own real/bounded/not-yet-scheduled shape. No scheduler is added -- ISS-2026-015 is a standing, accepted, repository-wide gap. */
export async function recalculateTenantVendorComplianceStatus(client: VendorComplianceMutationRpcClient, input: RecalculateTenantVendorComplianceStatusInput): Promise<VendorComplianceSweepResult> {
  const parsed = RecalculateTenantVendorComplianceStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("recalculate_tenant_vendor_compliance_status", {
    p_tenant_id: parsed.tenantId,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
    p_max_vendors: parsed.maxVendors ?? null,
  });
  if (error) throw new VendorComplianceMutationError(classifyError(error.message), error.message);
  return parseSweepResponse(data, "recalculate_tenant_vendor_compliance_status", "vendors_recalculated");
}
