/**
 * Multi-Region and Data Residency mutation primitives (IAE-033, Prompt 361).
 * Thin, typed wrappers around app.set_region_service_capability /
 * app.request_region_assignment / app.approve_region_assignment /
 * app.register_region_capability_exception / app.set_region_assignment_status
 * (supabase/migrations/20260808100000_create_intelligence_multi_region_data_residency.sql).
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  SetRegionServiceCapabilityInputSchema,
  RequestRegionAssignmentInputSchema,
  ApproveRegionAssignmentInputSchema,
  RegisterRegionCapabilityExceptionInputSchema,
  SetRegionAssignmentStatusInputSchema,
  parseRegionServiceCapability,
  parseTenantRegionAssignment,
  parseRegionCapabilityException,
  type SetRegionServiceCapabilityInput,
  type RequestRegionAssignmentInput,
  type ApproveRegionAssignmentInput,
  type RegisterRegionCapabilityExceptionInput,
  type SetRegionAssignmentStatusInput,
  type RegionServiceCapability,
  type TenantRegionAssignment,
  type RegionCapabilityException,
} from "../contracts/multi-region-data-residency/multi-region-data-residency.ts";

export type MultiRegionDataResidencyMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const MULTI_REGION_DATA_RESIDENCY_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "region_invalid_code",
  "region_invalid_service_category",
  "region_qualification_reason_required",
  "region_requires_dedicated_deployment",
  "region_capability_gap_unresolved",
  "region_capability_exception_not_needed",
  "region_exception_reason_required",
  "region_assignment_not_pending_review",
  "region_assignment_not_found",
  "region_invalid_transition",
  "region_rejection_reason_required",
] as const;
type KnownMultiRegionDataResidencyMutationErrorCode = (typeof MULTI_REGION_DATA_RESIDENCY_KNOWN_MUTATION_ERROR_CODES)[number];
export type MultiRegionDataResidencyMutationErrorCode = KnownMultiRegionDataResidencyMutationErrorCode | "mutation_failed" | "invalid_response";

export class MultiRegionDataResidencyMutationError extends Error {
  readonly code: MultiRegionDataResidencyMutationErrorCode;

  constructor(code: MultiRegionDataResidencyMutationErrorCode, message: string) {
    super(message);
    this.name = "MultiRegionDataResidencyMutationError";
    this.code = code;
  }
}

function classifyError(message: string): MultiRegionDataResidencyMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (MULTI_REGION_DATA_RESIDENCY_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "")
    ? (prefix as KnownMultiRegionDataResidencyMutationErrorCode)
    : "mutation_failed";
}

/** Authority: Supreme Admin only -- the capability matrix is platform-wide configuration no single tenant owns. */
export async function setRegionServiceCapability(client: MultiRegionDataResidencyMutationRpcClient, input: SetRegionServiceCapabilityInput): Promise<RegionServiceCapability> {
  const parsedInput = SetRegionServiceCapabilityInputSchema.parse(input);
  const { data, error } = await client.rpc("set_region_service_capability", {
    p_region_code: parsedInput.regionCode,
    p_service_category: parsedInput.serviceCategory,
    p_supported: parsedInput.supported,
    p_notes: parsedInput.notes,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MultiRegionDataResidencyMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MultiRegionDataResidencyMutationError("invalid_response", "set_region_service_capability returned no row");
  }
  return parseRegionServiceCapability(data as Record<string, unknown>);
}

/** Authority: DEPLOY:Configure. Fails with a real unique_violation (surfaced as mutation_failed) if this tenant already has a region assignment record. */
export async function requestRegionAssignment(client: MultiRegionDataResidencyMutationRpcClient, input: RequestRegionAssignmentInput): Promise<TenantRegionAssignment> {
  const parsedInput = RequestRegionAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("request_region_assignment", {
    p_tenant_id: parsedInput.tenantId,
    p_region_code: parsedInput.regionCode,
    p_qualification_reason: parsedInput.qualificationReason,
    p_contract_reference: parsedInput.contractReference,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MultiRegionDataResidencyMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MultiRegionDataResidencyMutationError("invalid_response", "request_region_assignment returned no row");
  }
  return parseTenantRegionAssignment(data as Record<string, unknown>);
}

/** Authority: DEPLOY:Approve. Enforces RPD-013's own "dedicated region requires dedicated deployment" rule and rejects until every service category is either genuinely supported or covered by a registered exception. */
export async function approveRegionAssignment(client: MultiRegionDataResidencyMutationRpcClient, input: ApproveRegionAssignmentInput): Promise<TenantRegionAssignment> {
  const parsedInput = ApproveRegionAssignmentInputSchema.parse(input);
  const { data, error } = await client.rpc("approve_region_assignment", {
    p_region_assignment_id: parsedInput.regionAssignmentId,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MultiRegionDataResidencyMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MultiRegionDataResidencyMutationError("invalid_response", "approve_region_assignment returned no row");
  }
  return parseTenantRegionAssignment(data as Record<string, unknown>);
}

/** Authority: DEPLOY:Approve -- the same tier as approving the assignment itself. Rejected if the underlying capability is already supported. */
export async function registerRegionCapabilityException(client: MultiRegionDataResidencyMutationRpcClient, input: RegisterRegionCapabilityExceptionInput): Promise<RegionCapabilityException> {
  const parsedInput = RegisterRegionCapabilityExceptionInputSchema.parse(input);
  const { data, error } = await client.rpc("register_region_capability_exception", {
    p_region_assignment_id: parsedInput.regionAssignmentId,
    p_service_category: parsedInput.serviceCategory,
    p_reason: parsedInput.reason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MultiRegionDataResidencyMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MultiRegionDataResidencyMutationError("invalid_response", "register_region_capability_exception returned no row");
  }
  return parseRegionCapabilityException(data as Record<string, unknown>);
}

/** Authority: DEPLOY:Configure. Enforces the real, ordered transition graph (pending_review -> rejected; approved -> active -> decommissioned). */
export async function setRegionAssignmentStatus(client: MultiRegionDataResidencyMutationRpcClient, input: SetRegionAssignmentStatusInput): Promise<TenantRegionAssignment> {
  const parsedInput = SetRegionAssignmentStatusInputSchema.parse(input);
  const { data, error } = await client.rpc("set_region_assignment_status", {
    p_region_assignment_id: parsedInput.regionAssignmentId,
    p_new_status: parsedInput.newStatus,
    p_rejection_reason: parsedInput.rejectionReason,
    p_actor_auth_user_id: parsedInput.actorAuthUserId,
    p_actor_label: parsedInput.actorLabel,
  });
  if (error) {
    throw new MultiRegionDataResidencyMutationError(classifyError(error.message), error.message);
  }
  if (!data || typeof data !== "object") {
    throw new MultiRegionDataResidencyMutationError("invalid_response", "set_region_assignment_status returned no row");
  }
  return parseTenantRegionAssignment(data as Record<string, unknown>);
}
