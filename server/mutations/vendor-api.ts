/**
 * Vendor API mutation entry points (IAE-011, Prompt 339). Thin, typed
 * wrappers around app.create_vendor_api_key /
 * app.submit_rfq_response_via_vendor_api /
 * app.accept_vendor_assignment_invitation_via_vendor_api /
 * app.decline_vendor_assignment_invitation_via_vendor_api
 * (supabase/migrations/20260804030000_create_intelligence_vendor_api.sql).
 * Revoke/rotate reuse ../mutations/api-key-webhook.ts's own revokeApiKey/
 * rotateApiKey directly -- unchanged, staff-only authority already covers a
 * vendor key (this migration's own design decision 9).
 */

import {
  CreateVendorApiKeyInputSchema,
  parseCreatedVendorApiKey,
  SubmitRfqResponseViaVendorApiInputSchema,
  parseRfqResponse,
  VendorAssignmentDecisionInputSchema,
  DeclineVendorAssignmentViaVendorApiInputSchema,
  parseVendorAssignmentInvitation,
  type CreateVendorApiKeyInput,
  type CreatedVendorApiKey,
  type SubmitRfqResponseViaVendorApiInput,
  type RfqResponse,
  type VendorAssignmentDecisionInput,
  type DeclineVendorAssignmentViaVendorApiInput,
  type VendorAssignmentInvitation,
} from "../contracts/vendor-api/vendor-api.ts";

export interface VendorApiMutationRpcClient {
  rpc(
    fn: "create_vendor_api_key" | "submit_rfq_response_via_vendor_api" | "accept_vendor_assignment_invitation_via_vendor_api" | "decline_vendor_assignment_invitation_via_vendor_api",
    args: Record<string, unknown>,
  ): Promise<{ data: unknown; error: { message: string } | null }>;
}

export const VENDOR_API_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "vendor_not_found",
  "vendor_not_active",
  "api_key_missing_name",
  "api_key_invalid_rate_limit",
  "api_key_invalid_expiry",
  "rfq_invitation_not_found",
  "invalid_transition",
  "rfq_response_deadline_passed",
  "idempotency_key_conflict",
  "vendor_assignment_invitation_not_found",
  "stale_version",
  "reason_required",
] as const;
type KnownVendorApiMutationErrorCode = (typeof VENDOR_API_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorApiMutationErrorCode = KnownVendorApiMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorApiMutationError extends Error {
  readonly code: VendorApiMutationErrorCode;

  constructor(code: VendorApiMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorApiMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorApiMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_API_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorApiMutationErrorCode) : "mutation_failed";
}

/** Authority: Supreme or the tenant's own active tenant_admin only -- a vendor cannot self-service (no vendor session/login exists). Returns the raw key exactly once. */
export async function createVendorApiKey(client: VendorApiMutationRpcClient, input: CreateVendorApiKeyInput): Promise<CreatedVendorApiKey> {
  const parsedInput = CreateVendorApiKeyInputSchema.parse(input);
  const { data, error } = await client.rpc("create_vendor_api_key", {
    p_tenant_id: parsedInput.tenantId,
    p_vendor_master_record_id: parsedInput.vendorMasterRecordId,
    p_name: parsedInput.name,
    p_expires_at: parsedInput.expiresAt,
    p_rate_limit_per_minute: parsedInput.rateLimitPerMinute,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new VendorApiMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorApiMutationError("invalid_response", "create_vendor_api_key returned no row");
  }
  return parseCreatedVendorApiKey(row as Record<string, unknown>);
}

/** Authority: vendor-scope containment -- the target invitation's own vendor_master_id must equal p_vendor_master_record_id. Idempotent on (tenant_id, idempotency_key). Rejects a late response outright (no override path via the Vendor API). */
export async function submitRfqResponseViaVendorApi(client: VendorApiMutationRpcClient, input: SubmitRfqResponseViaVendorApiInput): Promise<RfqResponse> {
  const parsedInput = SubmitRfqResponseViaVendorApiInputSchema.parse(input);
  const { data, error } = await client.rpc("submit_rfq_response_via_vendor_api", {
    p_tenant_id: parsedInput.tenantId,
    p_vendor_master_record_id: parsedInput.vendorMasterRecordId,
    p_rfq_invitation_id: parsedInput.rfqInvitationId,
    p_currency: parsedInput.currency,
    p_total_amount: parsedInput.totalAmount,
    p_validity_until: parsedInput.validityUntil,
    p_lead_time_days: parsedInput.leadTimeDays,
    p_commercial_terms: parsedInput.commercialTerms,
    p_vendor_confirmed: parsedInput.vendorConfirmed,
    p_idempotency_key: parsedInput.idempotencyKey,
  });
  if (error) {
    throw new VendorApiMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorApiMutationError("invalid_response", "submit_rfq_response_via_vendor_api returned no row");
  }
  return parseRfqResponse(row as Record<string, unknown>);
}

/** Authority: vendor-scope containment. Optimistic-concurrency-safe (record_version re-checked at the write, ATW-032 discipline). */
export async function acceptVendorAssignmentInvitationViaVendorApi(client: VendorApiMutationRpcClient, input: VendorAssignmentDecisionInput): Promise<VendorAssignmentInvitation> {
  const parsedInput = VendorAssignmentDecisionInputSchema.parse(input);
  const { data, error } = await client.rpc("accept_vendor_assignment_invitation_via_vendor_api", {
    p_tenant_id: parsedInput.tenantId,
    p_vendor_master_record_id: parsedInput.vendorMasterRecordId,
    p_invitation_id: parsedInput.invitationId,
    p_expected_version: parsedInput.expectedVersion,
  });
  if (error) {
    throw new VendorApiMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorApiMutationError("invalid_response", "accept_vendor_assignment_invitation_via_vendor_api returned no row");
  }
  return parseVendorAssignmentInvitation(row as Record<string, unknown>);
}

/** Authority: vendor-scope containment. Optimistic-concurrency-safe. */
export async function declineVendorAssignmentInvitationViaVendorApi(client: VendorApiMutationRpcClient, input: DeclineVendorAssignmentViaVendorApiInput): Promise<VendorAssignmentInvitation> {
  const parsedInput = DeclineVendorAssignmentViaVendorApiInputSchema.parse(input);
  const { data, error } = await client.rpc("decline_vendor_assignment_invitation_via_vendor_api", {
    p_tenant_id: parsedInput.tenantId,
    p_vendor_master_record_id: parsedInput.vendorMasterRecordId,
    p_invitation_id: parsedInput.invitationId,
    p_expected_version: parsedInput.expectedVersion,
    p_reason: parsedInput.reason,
  });
  if (error) {
    throw new VendorApiMutationError(classifyError(error.message), error.message);
  }
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorApiMutationError("invalid_response", "decline_vendor_assignment_invitation_via_vendor_api returned no row");
  }
  return parseVendorAssignmentInvitation(row as Record<string, unknown>);
}
