/**
 * Vendor Assignment mutation primitives (PRC-263, CG-S11-PRC-014). Thin, typed
 * wrappers around the write RPCs supabase/migrations/
 * 20260730720000_create_procurement_vendor_assignment.sql adds -- the same
 * KNOWN_MUTATION_ERROR_CODES / classifyError / callRpc shape
 * server/mutations/vendor-capacity.ts already establishes for this batch's own
 * template.
 */

import type { SupabaseClient } from "@supabase/supabase-js";
import {
  ProposeVendorAssignmentInvitationInputSchema,
  AcceptVendorAssignmentInvitationInputSchema,
  DeclineVendorAssignmentInvitationInputSchema,
  CancelVendorAssignmentInvitationInputSchema,
  ConfirmVendorAssignmentInputSchema,
  ReassignVendorAssignmentInputSchema,
  OverrideVendorAssignmentInputSchema,
  parseVendorAssignmentInvitation,
  type ProposeVendorAssignmentInvitationInput,
  type AcceptVendorAssignmentInvitationInput,
  type DeclineVendorAssignmentInvitationInput,
  type CancelVendorAssignmentInvitationInput,
  type ConfirmVendorAssignmentInput,
  type ReassignVendorAssignmentInput,
  type OverrideVendorAssignmentInput,
  type VendorAssignmentInvitation,
} from "../contracts/vendor-assignment/vendor-assignment.ts";

export type VendorAssignmentMutationRpcClient = Pick<SupabaseClient, "rpc">;

export const VENDOR_ASSIGNMENT_KNOWN_MUTATION_ERROR_CODES = [
  "insufficient_authority",
  "vendor_assignment_invitation_not_found",
  "shipment_order_not_found",
  "vendor_profile_not_found",
  "vendor_not_eligible",
  "vendor_no_longer_eligible",
  "reason_required",
  "idempotency_key_conflict",
  "invitation_conflict",
  "invalid_transition",
  "assignment_conflict",
  "already_assigned",
  "no_current_assignment",
  "invalid_role",
  "invalid_resource",
  "stale_version",
] as const;
type KnownVendorAssignmentMutationErrorCode = (typeof VENDOR_ASSIGNMENT_KNOWN_MUTATION_ERROR_CODES)[number];
export type VendorAssignmentMutationErrorCode = KnownVendorAssignmentMutationErrorCode | "mutation_failed" | "invalid_response";

export class VendorAssignmentMutationError extends Error {
  readonly code: VendorAssignmentMutationErrorCode;

  constructor(code: VendorAssignmentMutationErrorCode, message: string) {
    super(message);
    this.name = "VendorAssignmentMutationError";
    this.code = code;
  }
}

function classifyError(message: string): VendorAssignmentMutationErrorCode {
  const prefix = message.split(":")[0]?.trim();
  return (VENDOR_ASSIGNMENT_KNOWN_MUTATION_ERROR_CODES as readonly string[]).includes(prefix ?? "") ? (prefix as KnownVendorAssignmentMutationErrorCode) : "mutation_failed";
}

async function callRpc(client: VendorAssignmentMutationRpcClient, fn: string, args: Record<string, unknown>): Promise<unknown> {
  const { data, error } = await client.rpc(fn, args);
  if (error) {
    throw new VendorAssignmentMutationError(classifyError(error.message), error.message);
  }
  return data;
}

function requireInvitationRow(data: unknown, fn: string): VendorAssignmentInvitation {
  const row = Array.isArray(data) ? data[0] : data;
  if (!row || typeof row !== "object") {
    throw new VendorAssignmentMutationError("invalid_response", `${fn} returned no row`);
  }
  return parseVendorAssignmentInvitation(row as Record<string, unknown>);
}

/** PRC:Edit-gated (migration design note 1) -- eligibility (vendor/compliance/contract/PO/capacity) is enforced fresh server-side regardless of any client-side preview. */
export async function proposeVendorAssignmentInvitation(client: VendorAssignmentMutationRpcClient, input: ProposeVendorAssignmentInvitationInput): Promise<VendorAssignmentInvitation> {
  const parsed = ProposeVendorAssignmentInvitationInputSchema.parse(input);
  const data = await callRpc(client, "propose_vendor_assignment_invitation", {
    p_tenant_id: parsed.tenantId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_vendor_master_id: parsed.vendorMasterId,
    p_contract_id: parsed.contractId,
    p_po_id: parsed.poId,
    p_rate_version_id: parsed.rateVersionId,
    p_capacity_reservation_id: parsed.capacityReservationId,
    p_response_deadline: parsed.responseDeadline,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireInvitationRow(data, "propose_vendor_assignment_invitation");
}

export async function acceptVendorAssignmentInvitation(client: VendorAssignmentMutationRpcClient, input: AcceptVendorAssignmentInvitationInput): Promise<VendorAssignmentInvitation> {
  const parsed = AcceptVendorAssignmentInvitationInputSchema.parse(input);
  const data = await callRpc(client, "accept_vendor_assignment_invitation", {
    p_invitation_id: parsed.invitationId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireInvitationRow(data, "accept_vendor_assignment_invitation");
}

export async function declineVendorAssignmentInvitation(client: VendorAssignmentMutationRpcClient, input: DeclineVendorAssignmentInvitationInput): Promise<VendorAssignmentInvitation> {
  const parsed = DeclineVendorAssignmentInvitationInputSchema.parse(input);
  const data = await callRpc(client, "decline_vendor_assignment_invitation", {
    p_invitation_id: parsed.invitationId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireInvitationRow(data, "decline_vendor_assignment_invitation");
}

export async function cancelVendorAssignmentInvitation(client: VendorAssignmentMutationRpcClient, input: CancelVendorAssignmentInvitationInput): Promise<VendorAssignmentInvitation> {
  const parsed = CancelVendorAssignmentInvitationInputSchema.parse(input);
  const data = await callRpc(client, "cancel_vendor_assignment_invitation", {
    p_invitation_id: parsed.invitationId,
    p_expected_version: parsed.expectedVersion,
    p_reason: parsed.reason,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireInvitationRow(data, "cancel_vendor_assignment_invitation");
}

/** OPS:Assign-gated (migration design note 1) -- the canonical commitment, calls app.assign_resource (OPS-172, unchanged) and consumes any linked capacity reservation inline. */
export async function confirmVendorAssignment(client: VendorAssignmentMutationRpcClient, input: ConfirmVendorAssignmentInput): Promise<VendorAssignmentInvitation> {
  const parsed = ConfirmVendorAssignmentInputSchema.parse(input);
  const data = await callRpc(client, "confirm_vendor_assignment", {
    p_invitation_id: parsed.invitationId,
    p_expected_version: parsed.expectedVersion,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireInvitationRow(data, "confirm_vendor_assignment");
}

/** OPS:Assign-gated -- assigned -> superseded, and a brand-new invitation row (status=assigned immediately). Calls app.reassign_resource (OPS-172, unchanged). */
export async function reassignVendorAssignment(client: VendorAssignmentMutationRpcClient, input: ReassignVendorAssignmentInput): Promise<VendorAssignmentInvitation> {
  const parsed = ReassignVendorAssignmentInputSchema.parse(input);
  const data = await callRpc(client, "reassign_vendor_assignment", {
    p_invitation_id: parsed.invitationId,
    p_expected_version: parsed.expectedVersion,
    p_new_vendor_master_id: parsed.newVendorMasterId,
    p_new_contract_id: parsed.newContractId,
    p_new_po_id: parsed.newPoId,
    p_new_rate_version_id: parsed.newRateVersionId,
    p_new_capacity_reservation_id: parsed.newCapacityReservationId,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireInvitationRow(data, "reassign_vendor_assignment");
}

/** Requires BOTH OPS:Assign and PRC:Override (migration design note 1) -- governed emergency direct-assign bypassing the normal invite/accept/eligibility gate. Disclosed: no formal expiry/later-review workflow exists yet. */
export async function overrideVendorAssignment(client: VendorAssignmentMutationRpcClient, input: OverrideVendorAssignmentInput): Promise<VendorAssignmentInvitation> {
  const parsed = OverrideVendorAssignmentInputSchema.parse(input);
  const data = await callRpc(client, "override_vendor_assignment", {
    p_tenant_id: parsed.tenantId,
    p_shipment_order_id: parsed.shipmentOrderId,
    p_vendor_master_id: parsed.vendorMasterId,
    p_reason: parsed.reason,
    p_idempotency_key: parsed.idempotencyKey,
    p_actor_auth_user_id: parsed.actorAuthUserId,
    p_actor_label: parsed.actorLabel,
  });
  return requireInvitationRow(data, "override_vendor_assignment");
}
